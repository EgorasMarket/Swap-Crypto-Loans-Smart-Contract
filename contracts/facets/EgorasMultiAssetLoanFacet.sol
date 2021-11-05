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
}
contract EgorasMultiAssetLoanFacet {
/* ========== LIBRARIES ========== */
    using SafeMath for uint;
    using SafeDecimalMath for uint;
    uint private _BCRATIO = 150 ether;
    uint private _ACRATIO = 100 ether;
   modifier onlyOwner{
        require(msg.sender == LibDiamond.contractOwner(), "Access denied, Only owner is allowed!");
        _;
    }
    event Listed(
        address _base,
        address _asset,
        address _secretary,
        bool _live,
        uint _maxLoan,
        string _ticker,
        address _creator,
        uint _time
    );
    struct LoanAssetMeta{
        address base;
        address asset;
        address secretary;
        bool live;
        uint maxLoan;
        string ticker;
        address creator;
    }
    LoanAssetMetas[] loanAssetMetas;
    mapping(bytes => bool) listed;
    mapping(bytes => uint) lookup;

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

    function _open(
        uint _collateral,
        uint _amount,
        string memory _ticker
        ) internal{
        require(_maxloan(_collateral, _ticker), "No liquidity!");

    }

    function _maxloan(uint _collateral, string memory _ticker) internal returns(bool) {
        PRICEORACLE p = PRICEORACLE(address(this));
        uint xrate = p.price(_ticker);
        uint value = x.multiplyDecimalRound(_collateral);
        bytes key = lookup[p.converter(_ticker)];
        LoanAssetMeta memory l = LoanAssetMetas[key];
        return l.maxLoan >= value ? false : true;
    }

    function _maxDraw(uint _collateral, string memory _ticker) internal returns (uint){
        
    }

    function _liquidationPrice(uint _collateral, uint _maxDrawAmount) internal returns(uint){
        return 
    }
    function getPrice(string memory _ticker) external view returns (uint256) {
        PRICEORACLE p = PRICEORACLE(address(this));
        return p.price(_ticker);
    }


    fallback() external payable {}

    receive() external payable {}
}
