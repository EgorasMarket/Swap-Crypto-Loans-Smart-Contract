// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;
pragma experimental ABIEncoderV2;
import "../libraries/LibDiamond.sol";
import "../libraries/SafeDecimalMath.sol";
import "../libraries/SafeMath.sol";
interface PRICEORACLE {
    /// @notice Gets price of a ticker ie ETH-EUSD.
    /// @return current price of a ticker
    function price(string memory _ticker) external view returns (uint256);

    /// @notice converts string to bytes.
    /// @return bytes
    function converter(string memory _ticker) external view returns (bytes memory);
}
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    function mint(address account, uint256 amount) external  returns (bool);
    function burnFrom(address account, uint256 amount) external returns (bool);
}
contract EgorasMultiAssetLoanFacet {
/* ========== LIBRARIES ========== */
    using SafeMath for uint;
    using SafeDecimalMath for uint;
    uint private _BCRATIO;
    uint private _ACRATIO;
    uint private _LOANABLE; // 65%
    uint private _PENALTY; // 35%
    uint private _DIVISOR;
   modifier onlyOwner{
        require(_msgSender() == LibDiamond.contractOwner(), "Access denied, Only owner is allowed!");
        _;
    }
    event Listed(
        address _base,
        address _asset,
        address indexed _secretary,
        bool _live,
        uint _maxLoan,
        string _ticker,
        address _creator,
        uint _time
    );
    event LoanCreated(
        address indexed _user,
        uint _id,
        uint _amount,
        uint _collateral,
        string _ticker,
        uint lqp,
        uint _maxDraw,
        uint _time
        );
    event Topped(
        uint id,
        uint _totalCollateral,
        uint _maxDraw,
        uint _newLqp,
        uint _time);
    event Liquidated(
        address indexed _liquidateBy,
        uint id,
        uint _penalty,
        uint _lAmount,
        uint _time);
    event Repaid(
        uint id,
        uint _time);
    event Withdrew(
        uint id,
        uint debt,
        uint liquidationPrice,
        uint _time);
    struct LoanAssetMeta{
        address base;
        address asset;
        address secretary;
        bool live;
        uint maxLoan;
        string ticker;
        address creator;
    }
    struct Loan{
        uint id;
        address user;
        uint collateral;
        bytes ticker;
        uint debt;
        uint max;
        uint liquidationPrice;
        bool stale;
    }
    uint private loanids;
    LoanAssetMeta[] private loanAssetMetas;
    Loan[] private loans;
    mapping(bytes => bool) listed;
    mapping(bytes => uint) lookup;
    mapping(address => mapping(bytes => bool)) pendingLoan;
    mapping(address => mapping(bytes => uint)) lastestLoan;


    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
    function list(
        address _base, address _asset,
        address _secretary, bool _live,
        string memory _ticker,
        uint _maxLoan
    ) external onlyOwner{
      PRICEORACLE p = PRICEORACLE(address(this));
      require(p.price(_ticker) > 0, "Price not found");
      bytes memory __ticker = p.converter(_ticker);
      require(!listed[__ticker],  "Ticker already exit!");
      LoanAssetMeta memory _loanAssetMeta = LoanAssetMeta({
            base: _base,
            asset: _asset,
            secretary: _secretary,
            ticker: _ticker,
            live: _live,
            maxLoan: _maxLoan,
            creator: _msgSender()
      });
      loanAssetMetas.push(_loanAssetMeta);
      uint256 _lookup = loanAssetMetas.length - 1;
      lookup[__ticker] = _lookup;
      listed[__ticker] = true;
    emit Listed(
        _base,
        _asset,
        _secretary,
        _live,
        _maxLoan,
        _ticker,
        _msgSender(),
        block.timestamp
    );

    }
function open(
     uint _collateral,
     uint _amount,
     string memory _ticker
) external{
PRICEORACLE p = PRICEORACLE(address(this));
require(!pendingLoan[_msgSender()][p.converter(_ticker)], "You have pending loan!");
uint _maxDraw;
uint lqp;
LoanAssetMeta storage _l; 
PRICEORACLE _p;
(_maxDraw, lqp, _l, _p) = _open(_collateral, _amount, _ticker);
_tranferLoan(_collateral, _l, _amount);
_saveLoan(_collateral,_amount,_maxDraw,lqp,_ticker, _p, _l);
}
 function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
function openDefaultAsset(
    uint _amount,
    string memory _ticker) external payable{
    uint _collateral = msg.value;
    PRICEORACLE p = PRICEORACLE(address(this));
require(!pendingLoan[_msgSender()][p.converter(_ticker)], "You have pending loan!");
uint _maxDraw;
uint lqp;
LoanAssetMeta storage _l;
PRICEORACLE _p;
(_maxDraw, lqp, _l, _p) = _open(_collateral, _amount, _ticker);
_mint(_l.base, _msgSender(), _amount);
_saveLoan(_collateral,_amount,_maxDraw,lqp,_ticker, _p, _l);
}
function getLastestLoan(address _borrower, string memory _ticker) external view returns(
    uint _collateral,
    uint _debt,
    uint _max,
    uint _liquidationPrice,
    bool _stale,
    uint _id
    ){
    PRICEORACLE p = PRICEORACLE(address(this));
    uint id = lastestLoan[_borrower][p.converter(_ticker)];
    Loan memory loan = loans[id];
    return(
        loan.collateral,
        loan.debt,
        loan.max,
        loan.liquidationPrice,
        loan.stale,
        loan.id
    );
}
    function _open(
        uint _collateral,
        uint _amount,
        string memory _ticker
        ) internal view returns(uint, uint, LoanAssetMeta storage _l, PRICEORACLE _p){
        require(_collateral > 0,"Collateral must be greater than zero!");
        require(_amount > 0,"Collateral must be greater than zero!");
        PRICEORACLE p = PRICEORACLE(address(this));
        require(_maxloan(_collateral, _ticker), "No liquidity!");
        uint _maxDraw = __maxDraw(_collateral, _ticker);
        require(_maxDraw <= _amount, "Max loan exceeded!");
        uint lqp = __liquidationPrice(_collateral, _amount);
        uint _lookup = lookup[p.converter(_ticker)];
        ////
        LoanAssetMeta storage l = loanAssetMetas[_lookup];
        return(_maxDraw, lqp, l, p);
}

        function _tranferLoan(uint _collateral, LoanAssetMeta storage l, uint _amount) internal{
        require(_collateral <= IERC20(l.asset).allowance(_msgSender(), address(this)), "Allowance not high enough");
        require(IERC20(l.asset).transferFrom(_msgSender(), address(this), _collateral), "Error");
        require(IERC20(l.base).mint(_msgSender(),  _amount), "Unable to mint!");
        }
        function _mint(address _c, address _r, uint _a) internal{
             require(IERC20(_c).mint(_r,  _a), "Unable to mint!");
        }
        function _saveLoan(uint _collateral, uint _amount, uint _maxDraw, uint  lqp, string memory _ticker, PRICEORACLE p, LoanAssetMeta storage l) internal {
        
         Loan memory loan = Loan({
           id: loans.length,
            user: _msgSender(),
            collateral: _collateral,
            ticker: p.converter(_ticker),
            debt: _amount,
            max: _maxDraw,
            liquidationPrice: lqp,
            stale: false
        });
      loans.push(loan);
      uint256 id = loans.length - 1;
        
            l.maxLoan = l.maxLoan.sub(_amount);
            lastestLoan[_msgSender()][p.converter(_ticker)] = id;
            pendingLoan[_msgSender()][p.converter(_ticker)] = true;
            emit LoanCreated(_msgSender(), id, _amount, _collateral, _ticker, lqp, _maxDraw, block.timestamp);
        }

    function _maxloan(uint _collateral, string memory _ticker) internal view returns(bool) {
        PRICEORACLE p = PRICEORACLE(address(this));
        uint xrate = p.price(_ticker);
        uint value = xrate.multiplyDecimal(_collateral);
        uint key = lookup[p.converter(_ticker)];
        LoanAssetMeta memory l = loanAssetMetas[key];
        return l.maxLoan >= value ? true : false;
    }

    function __maxDraw(uint _collateral, string memory _ticker) internal view returns (uint){
         PRICEORACLE p = PRICEORACLE(address(this));
         uint xrate = p.price(_ticker);
         uint cAmount = xrate.multiplyDecimal(_collateral);
         return uint(uint(cAmount).divideDecimal(uint(_DIVISOR)).multiplyDecimal(uint(_LOANABLE)));
        
    }
    
    function repay(uint id, uint _amount, bool isDefault, bool isBurn) external payable
    {
        Loan storage loan = loans[id];
        uint _lookup = lookup[loan.ticker];
        require(loan.user == _msgSender(), "Access denied!");
        require(!loan.stale, "Loan has been repaid or liquidated!");
        require(loan.debt == _amount, "Invalid repayment amount");
        LoanAssetMeta storage l = loanAssetMetas[_lookup];
        require(_amount <= IERC20(l.base).allowance(_msgSender(), address(this)), "Allowance not high enough");
        isBurn ? require(IERC20(l.base).burnFrom(_msgSender(), _amount), "Error") : require(IERC20(l.base).transferFrom(_msgSender(), address(this), _amount), "Error");
        isDefault ? payable(loan.user).transfer(loan.collateral) : require(IERC20(l.asset).transfer(_msgSender(), loan.collateral), "Error");
        l.maxLoan = l.maxLoan.add(_amount);
        loan.stale = true;
        pendingLoan[_msgSender()][loan.ticker] = false;
        emit Repaid(id, block.timestamp);
    }
    // 
    function liquidateMany(uint[] calldata _id, string[] calldata _tickers, bool[] calldata _isDefault) external{
           for (uint256 i; i < _id.length; i++) {
            this.liquidate(_id[i], _tickers[i], _isDefault[i]);
          }
    }

    function liquidate(uint id, string memory _ticker, bool isDefault) external payable{
        PRICEORACLE p = PRICEORACLE(address(this));
        Loan storage loan = loans[id];
        uint _lookup = lookup[loan.ticker];
        require(!loan.stale, "Loan has been repaid or liquidated!");
        require(p.price(_ticker) >= loan.liquidationPrice, "You can't liquidate this loan!");
        uint _lAmount = _liquidationAmount(id, _ticker);
        require(_lAmount > 0, "Liquidation amount can't be zero");
        uint _penalty = __penalty(_lAmount);
        LoanAssetMeta storage l = loanAssetMetas[_lookup];
        l.maxLoan = l.maxLoan.add(loan.debt);
        isDefault ? payable(loan.user).transfer(_lAmount.sub(_penalty)) : require(IERC20(l.asset).transfer(loan.user, _lAmount.sub(_penalty)), "Error");
        pendingLoan[_msgSender()][loan.ticker] = false;
        loan.stale = true;
        emit Liquidated(_msgSender(), id, _penalty, _lAmount, block.timestamp);
    }

    function _liquidationAmount(uint id, string memory _ticker) internal view returns (uint){
     PRICEORACLE p = PRICEORACLE(address(this));
      Loan memory loan = loans[id];
      uint _debt = loan.debt;
    //   uint _collateral = loan.collateral;
      uint _xrate = p.price(_ticker);
      uint _lAmount = _debt.divideDecimal(_xrate);
    //   uint __lAmount =   _collateral >= _lAmount ? _collateral.sub(_lAmount) : 0;
      return _lAmount;
    }

    function __penalty(uint _lAmount) internal view returns (uint){
        return uint(uint(_PENALTY).divideDecimal(uint(_DIVISOR)).multiplyDecimal(uint(_lAmount)));
    }
    function draw(uint id, uint _amount) external{
        Loan storage loan = loans[id];
        uint _lookup = lookup[loan.ticker];
        require(loan.user == _msgSender(), "Access denied!");
        require(!loan.stale, "Loan has been repaid or liquidated!");
        require(loan.max >= loan.debt.add(_amount), "Not enough loan!");
        LoanAssetMeta memory l = loanAssetMetas[_lookup];
        require(IERC20(l.base).mint(_msgSender(),  _amount), "Unable to mint!");
         uint _newLqp = __liquidationPrice(loan.collateral, loan.debt.add(_amount));
        loan.liquidationPrice = _newLqp;
        loan.debt = loan.debt.add(_amount);
        emit Withdrew(id, loan.debt, loan.liquidationPrice, block.timestamp);
    }

    function _topup(uint id, string memory _ticker, uint _collateral)
    internal view returns(uint, uint, uint, LoanAssetMeta memory _l, Loan storage _loan){
        Loan storage loan = loans[id];
        require(loan.user == _msgSender(), "Access denied!");
        require(!loan.stale, "Loan has been repaid or liquidated!");
        uint _totalCollateral = loan.collateral.add(_collateral);
        uint _newLqp = __liquidationPrice(_totalCollateral, loan.debt);
        uint _maxDraw = __maxDraw(_totalCollateral, _ticker);
        uint _lookup = lookup[loan.ticker];
        LoanAssetMeta memory l = loanAssetMetas[_lookup];
        return(_totalCollateral, _newLqp, _maxDraw, l, loan);
    }
    function topupDefaultAsset(uint id, string memory _ticker) external payable{
        require(msg.value > 0, "Collateral must be greater than zero!");
        uint _totalCollateral;
        uint _newLqp;
        uint _maxDraw;
        LoanAssetMeta memory _l;
        Loan storage _loan;
        (_totalCollateral, _newLqp, _maxDraw, _l, _loan) = _topup(id, _ticker, msg.value);
        _updateLoan(_totalCollateral, _newLqp,_maxDraw, id, _loan);
    }
    function topup(uint id, string memory _ticker, uint _collateral) external{
      require(_collateral > 0, "Collateral must be greater than zero!");
      uint _totalCollateral;
      uint _newLqp;
      uint _maxDraw;
      LoanAssetMeta memory _l;
      Loan storage _loan;
      (_totalCollateral, _newLqp, _maxDraw, _l, _loan) = _topup(id, _ticker, _collateral);
       _tranferFrom(_collateral,  _l);
       _updateLoan(_totalCollateral, _newLqp,_maxDraw, id, _loan);
    }

    function _updateLoan(uint _totalCollateral, uint _newLqp, uint _maxDraw, uint id, Loan storage loan) internal{
        loan.collateral = _totalCollateral;
        loan.liquidationPrice = _newLqp;
        loan.max = _maxDraw;
        emit Topped(id, _totalCollateral, _maxDraw, _newLqp, block.timestamp);
    }


    function _tranferFrom(uint _collateral, LoanAssetMeta memory l) internal{
        require(_collateral <= IERC20(l.asset).allowance(_msgSender(), address(this)), "Allowance not high enough");
        require(IERC20(l.asset).transferFrom(_msgSender(), address(this), _collateral), "Error");
    }
    function __liquidationPrice(uint _collateral, uint _maxDrawAmount) internal view returns(uint){
        return _BCRATIO.multiplyDecimal(_maxDrawAmount).divideDecimal(_ACRATIO.multiplyDecimal(_collateral));
    }

function __tickerInfo(string memory _ticker) external view returns(LoanAssetMeta memory _meta) {
    PRICEORACLE p = PRICEORACLE(address(this));
    uint _lookup = lookup[p.converter(_ticker)];
    LoanAssetMeta memory l = loanAssetMetas[_lookup];
    return(l);
    }

function __getLoanInfo(string memory _ticker, address _user) external view returns(Loan memory _loan){
    PRICEORACLE p = PRICEORACLE(address(this));
    uint _lookup = lastestLoan[_user][p.converter(_ticker)];
    Loan memory l = loans[_lookup];
    return(l);
}
function getTickerInfo(string memory _ticker) external view returns(address, address, bool, uint, address, address) {
    PRICEORACLE p = PRICEORACLE(address(this));
    uint _lookup = lookup[p.converter(_ticker)];
    LoanAssetMeta memory l = loanAssetMetas[_lookup];
    return(l.base, l.asset, l.live, l.maxLoan, l.secretary, l.creator);
}
function __getLoanInfoByID(uint id) external view returns(Loan memory _loan){
    Loan memory l = loans[id];
    return(l);
}

function ___pendingLoan(address _user, string memory _ticker) external view returns(bool){
    PRICEORACLE p = PRICEORACLE(address(this));
    return pendingLoan[_user][p.converter(_ticker)];
}

function initvars(uint _DIVISORw, uint _BCRATIOw, uint _ACRATIOw, uint _LOANABLEw, uint _PENALTYw ) external onlyOwner{
    _BCRATIO = _BCRATIOw;
    _ACRATIO = _ACRATIOw;
    _LOANABLE = _LOANABLEw;
    _PENALTY = _PENALTYw; 
    _DIVISOR = _DIVISORw;
}


}