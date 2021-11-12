// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;
pragma experimental ABIEncoderV2;
import "../libraries/LibDiamond.sol";
import "../libraries/SafeDecimalMath.sol";
interface PRICEORACLE {
    /// @notice Gets price of a ticker ie ETH-EUSD.
    /// @return current price of a ticker
    function price(string memory _ticker) external view returns (uint256);

    /// @notice converts string to bytes.
    /// @return bytes
    function converter(string memory _ticker) external view returns (uint256);
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
    uint private _BCRATIO = 150 ether;
    uint private _ACRATIO = 100 ether;
    uint private _LOANABLE = 6500; // 65%
    uint private _PENALTY = 3500; // 35%
    uint private _DIVISOR = 10000;
   modifier onlyOwner{
        require(msg.sender == LibDiamond.contractOwner(), "Access denied, Only owner is allowed!");
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
    LoanAssetMetas[] loanAssetMetas;
    Loans[] loans;
    mapping(bytes => bool) listed;
    mapping(bytes => uint) lookup;
    mapping(address => mapping(bytes => bool)) pendingLoan;
    mapping(address => mapping(bytes => uint)) lastestLoan;

constructor() public payable {
}
    function list(
        address _base, address _asset,
        address _secretary, bool _live,
        string memory _ticker,
        uint _maxLoan
    ) external onlyOwner{
      PRICEORACLE p = PRICEORACLE(address(this));
      require(p.price(_ticker) > 0, "Price not found");
      bytes __ticker = p.converter(_ticker);
      require(!listed[__ticker],  "Ticker already exit!");
      LoanAssetMeta memory _loanAssetMeta = LoanAssetMeta({
            base: _base,
            asset: _asset,
            secretary: _secretary,
            ticker: _ticker,
            live: _live,
            maxLoan: _maxLoan,
            creator: msg.sender
      });
      LoanAssetMetas.push(_loanAssetMeta);
      uint256 _lookup = LoanAssetMetas.length - 1;
      lookup[__ticker] = _lookup;

    emit Listed(
        _base,
        _asset,
        _secretary,
        _live,
        _maxLoan,
        _ticker,
        msg.sender,
        block.timestamp
    );

    }
function open(
     uint _collateral,
     uint _amount,
     string memory _ticker
) external{
PRICEORACLE p = PRICEORACLE(address(this));
require(!pendingLoan[msg.sender][p.converter(_ticker)], "You have pending loan!");
uint _maxDraw;
uint lqp;
LoanAssetMeta l;
PRICEORACLE p; 
(_maxDraw, lqp, l, p) = this._open(_collateral, _amount, _ticker);
_tranferLoan(_collateral, l, _amount);
_saveLoan(_collateral,_amount,_maxDraw,lqp,_ticker, p);
}

function openDefaultAsset(
    uint _amount,
    string memory _ticker) external payable{
    uint _collateral = msg.value;
    PRICEORACLE p = PRICEORACLE(address(this));
require(!pendingLoan[msg.sender][p.converter(_ticker)], "You have pending loan!");
uint _maxDraw;
uint lqp;
LoanAssetMeta l;
PRICEORACLE p;
(_maxDraw, lqp, l, p) = this._open(_collateral, _amount, _ticker);
_mint(l.base, msg.sender, _amount);
_saveLoan(_collateral,_amount,_maxDraw,lqp,_ticker, p);
}
function lastestLoan(address _borrower, string memory _ticker) external view returns(
    uint _collateral,
    uint _debt,
    uint _max,
    uint _liquidationPrice,
    bool _stale,
    uint id
    ){
    PRICEORACLE p = PRICEORACLE(address(this));
    uint id = lastestLoan[msg.sender][p.converter(_ticker)];
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
        ) internal pure returns(uint, uint LoanAssetMeta, PRICEORACLE){
        require(_collateral > 0,"Collateral must be greater than zero!");
        require(_amount > 0,"Collateral must be greater than zero!");
        PRICEORACLE p = PRICEORACLE(address(this));
        require(!this._maxloan(_collateral, _ticker), "No liquidity!");
        uint _maxDraw = this._maxDraw(_collateral, _ticker);
        require(_maxDraw >= _amount, "Max loan exceeded!");
        uint lqp = this._liquidationPrice(_collateral, _amount);
        uint _lookup = lookup[p.converter(_ticker)];
        ////
        LoanAssetMeta storage l = LoanAssetMetas[_lookup];
        return(_maxDraw, lqp, l, p);
}

        function _tranferLoan(uint _collateral, LoanAssetMeta l, uint _amount) internal{
        require(_collateral <= IERC20(l.asset).allowance(msg.sender, address(this)), "Allowance not high enough");
        require(IERC20(l.asset).transferFrom(msg.sender, address(this), _collateral), "Error");
        require(IERC20(l.base).mint(msg.sender,  _amount), "Unable to mint!");
        }
        function _mint(address _c, address _r, _a) internal{
             require(IERC20(_c).mint(_r,  _a), "Unable to mint!");
        }
        function _saveLoan(uint _collateral, uint _amount, uint _maxDraw, uint  lqp, string _ticker, PRICEORACLE p) internal {
         uint id = loanids.add(1);
         loans[id] = Loan({
            id: id,
            user: msg.sender,
            collateral: _collateral,
            ticker: p.converter(_ticker),
            debt: _amount,
            max: _maxDraw,
            liquidationPrice: lqp,
            stale: false
        });
            l.maxLoan = l.maxLoan.sub(_amount);
            lastestLoan[msg.sender][p.converter(_ticker)] = id;
            pendingLoan[msg.sender][p.converter(_ticker)] = true;
            emit LoanCreated(msg.sender, id, _amount, _collateral, _ticker, lqp, _maxDraw, block.timestamp);
        }

    function _maxloan(uint _collateral, string memory _ticker) internal returns(bool) {
        PRICEORACLE p = PRICEORACLE(address(this));
        uint xrate = p.price(_ticker);
        uint value = x.multiplyDecimalRound(_collateral);
        uint key = lookup[p.converter(_ticker)];
        LoanAssetMeta memory l = LoanAssetMetas[key];
        return l.maxLoan >= value ? true : false;
    }

    function _maxDraw(uint _collateral, string memory _ticker) internal returns (uint){
         PRICEORACLE p = PRICEORACLE(address(this));
         uint xrate = p.price(_ticker);
         uint cAmount = xrate.multiplyDecimalRound(_collateral);
         return uint(uint(cAmount).divideDecimalRound(uint(_DIVISOR)).multiplyDecimalRound(uint(_LOANABLE)));
        
    }
    function repay(uint id, uint _amount, bool isDefault) external
    {
        Loan storage loan = loans[id];
        uint _lookup = lookup[loan.ticker];
        require(loan.user == msg.sender, "Access denied!");
        require(loan.stale, "Loan has been repaid or liquidated!");
        require(loan.debt == _amount, "Invalid repayment amount");
        LoanAssetMeta storage l = LoanAssetMetas[_lookup];
        require(_amount <= IERC20(l.base).allowance(msg.sender, address(this)), "Allowance not high enough");
        require(IERC20(l.base).burnFrom(msg.sender, _amount), "Error");
        isDefault ? loan.user.transfer(loan.collateral) : require(IERC20(l.asset).transfer(msg.sender, loan.collateral), "Error");
        l.maxLoan = l.maxLoan.add(_amount);
        loan.stale = true;
        pendingLoan[msg.sender][loan.ticker] = false;
        emit Repaid(id, block.timestamp);
    }

    function liquidate(uint id, string memory _ticker, bool isDefault) external{
        PRICEORACLE p = PRICEORACLE(address(this));
        Loan storage loan = loans[id];
        uint _lookup = lookup[loan.ticker];
        require(loan.stale, "Loan has been repaid or liquidated!");
        require(p.price(_ticker) >= loan.liquidationPrice, "You can't liquidate this loan!");
        uint _lAmount = this._liquidationAmount(id, _ticker);
        require(_lAmount > 0, "Liquidation amount can't be zero");
        uint _penalty = this._penalty(lAmount);
        LoanAssetMeta storage l = LoanAssetMetas[_lookup];
        l.maxLoan = l.maxLoan.add(loan.debt);
        isDefault ? loan.user.transfer(_lAmount.sub(_penalty)) : require(IERC20(l.asset).transfer(loan.user, _lAmount.sub(_penalty)), "Error");
        pendingLoan[msg.sender][loan.ticker] = false;
        emit Liquidated(msg.sender, id, _penalty, _lAmount, block.timestamp);
    }

    function _liquidationAmount(uint id, string memory _ticker) internal returns (uint){
     PRICEORACLE p = PRICEORACLE(address(this));
      Loan memory loan = loans[id];
      uint _debt = loan.debt;
      uint _collateral = loan.collateral;
      uint _xrate = p.price(_ticker);
      var _lAmount = _debt.divideDecimalRound(_xrate);
      var __lAmount =   _collateral >= _lAmount ? _collateral.sub(_lAmount) : 0;
      return __lAmount;
    }

    function _penalty(uint _lAmount) internal returns (uint){
        return uint(uint(_PENALTY).divideDecimalRound(uint(_DIVISOR)).multiplyDecimalRound(uint(_lAmount)));
    }
    function draw(uint id, uint _amount) external{
        Loan storage loan = loans[id];
        uint _lookup = lookup[loan.ticker];
        require(loan.user == msg.sender, "Access denied!");
        require(loan.stale, "Loan has been repaid or liquidated!");
        require(loan.max >= loan.debt.add(_amount), "Not enough loan!");
        LoanAssetMeta memory l = LoanAssetMetas[_lookup];
        require(IERC20(l.base).mint(msg.sender,  _amount), "Unable to mint!");
         uint _newLqp = this._liquidationPrice(loan.collateral, loan.debt.add(_amount));
        loan.liquidationPrice = _newLqp;
        loan.debt = loan.debt.add(_amount);
        emit Withdrew(id, loan.debt, loan.liquidationPrice, block.timestamp);
    }

    function _topup(uint id, string memory _ticker, uint _collateral)
    internal pure returns(uint, uint, uint, LoanAssetMeta memory l, Loan storage loan){
        Loan storage loan = loans[id];
        require(loan.user == msg.sender, "Access denied!");
        require(loan.stale, "Loan has been repaid or liquidated!");
        uint _totalCollateral = loan.add(_collateral);
        uint _newLqp = this._liquidationPrice(_totalCollateral, loan.debt);
        uint _maxDraw = this._maxDraw(_totalCollateral, _ticker);
        uint _lookup = lookup[loan.ticker];
        LoanAssetMeta memory l = LoanAssetMetas[_lookup];
        return(_totalCollateral, _newLqp, _maxDraw, l, loan);
    }
    function topupDefaultAsset(uint id, string memory _ticker) external payable{
        require(msg.value > 0, "Collateral must be greater than zero!");
        uint _totalCollateral;
        uint _newLqp;
        uint _maxDraw;
        LoanAssetMeta memory l;
        Loan storage loan;
        (_totalCollateral, _newLqp, _maxDraw, l, loan) = _topup(id, _ticker, msg.value);
        _updateLoan(_totalCollateral, _newLqp,_maxDraw, id, loan);
    }
    function topup(uint id, string memory _ticker, uint _collateral) external{
      require(_collateral > 0, "Collateral must be greater than zero!");
      uint _totalCollateral;
      uint _newLqp;
      uint _maxDraw;
      LoanAssetMeta memory l;
      Loan storage loan;
      (_totalCollateral, _newLqp, _maxDraw, l, loan) = _topup(id, _ticker, _collateral);
       _tranferFrom(_collateral,  l);
       _updateLoan(_totalCollateral, _newLqp,_maxDraw, id, loan);
    }

    function _updateLoan(uint _totalCollateral, uint _newLqp, uint _maxDraw, uint id, Loan storage loan) internal{
        loan.collateral = _totalCollateral;
        loan.liquidationPrice = _newLqp;
        loan.max = _maxDraw;
        emit Topped(id, _totalCollateral, _maxDraw, _newLqp, block.timestamp);
    }


    function _tranferFrom(uint _collateral, LoanAssetMeta memory l) internal{
        require(_collateral <= IERC20(l.asset).allowance(msg.sender, address(this)), "Allowance not high enough");
        require(IERC20(l.asset).transferFrom(msg.sender, address(this), _collateral), "Error");
    }
    function _liquidationPrice(uint _collateral, uint _maxDrawAmount) internal returns(uint){
        return _BCRATIO.multiplyDecimalRound(_maxDrawAmount).divideDecimalRound(_ACRATIO.multiplyDecimalRound(_collateral));
    }

    fallback() external payable {}

    receive() external payable {}
}
