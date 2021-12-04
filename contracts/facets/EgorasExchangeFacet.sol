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

interface LAONMETA {
  function getTickerInfo(string memory _ticker) external view returns(address, address, bool, uint, address, address);
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

contract EgorasExchangeFacet{
     event Bought(uint _price, uint _amount, uint _value, string _ticker, bool _isBase, uint time);
   struct LoanMeta{
        address base;
        address asset;
        address secretary;
        bool live;
        uint maxLoan;
        address creator;
    }


function getTickerMeta(string memory _ticker) external view returns(LoanMeta memory){
    LAONMETA lm = LAONMETA(address(this));
    address base;
    address asset;
    bool live;
    address secretary;
    uint maxLoan;
    address creator;
    LoanMeta memory l;
    (base, asset, live, maxLoan, secretary, creator) = lm.getTickerInfo(_ticker);
    l.base = base;
    l.asset = asset;
    l.live = live;
    l.maxLoan = maxLoan;
    l.secretary = secretary;
    l.creator = creator;
    return(l);
}

    function _tFrom(address _contract, uint _amount) internal{
        require(IERC20(_contract).allowance(msg.sender, address(this)) >= _amount, "Non-sufficient funds");
        require(IERC20(_contract).transferFrom(msg.sender, address(this), _amount), "Fail to tranfer fund");
    }
    function _bOf(address _contract, address _rec) internal returns(uint){
        return ERC20(_contract).balanceOf(_rec);
    }
     function _bd(address _rec) internal returns(uint){
        return _rec.balance;
    }
    function _tr(uint _amount, address _rec, address _contract) internal{
        require(ERC20(_contract).transfer(_rec, _amount), "Fail to tranfer fund");
    }
    function _trd(uint _amount, address _rec) internal{
        payable(_rec).transfer(_amount);
    }
    
    function _getContract(string memory _ticker, bool _isBase) internal returns (address) {
        LoanMeta memory l = this.getTickerMeta(_ticker);
        require(l.base !== address(0) && l.asset !== address(0), "Pair not found!");
        return _isBase ? l.base : l.asset;
    }
    function _getPr(string memory _ticker) internal returns (uint) {
        PRICEORACLE p = PRICEORACLE(address(this));
        return p.price(_ticker);
    }
    function _getAmount(uint _marketPrice, uint _amount, bool _isBase) internal returns (uint) {
        return _isBase ? _amount.divideDecimal(_marketPrice) : _amount.multiplyDecimal(_marketPrice);
    }
    function exchange(string memory _ticker, uint _amount, bool _isBase) external{
        require(_amount > 0, "Zero value provided!");
        _tFrom(getContract(_ticker,_isBase), _amount);
        uint _marketPrice = _getPr(_ticker);
        uint _getAmount = _getAmount(_marketPrice, _amount, _isBase);
        require(_bOf(getContract(_ticker,_isBase), address(this)) >= _getAmount, "No fund to execute the trade");
        _tr(getAmount, msg.sender, getContract(_ticker, !_isBase))
        emit Bought(_marketPrice, _amount, getAmount, _ticker, _isBase, block.timestamp); 
    }

    function getDefault(string memory _ticker, uint _amount) external{
        require(_amount > 0, "Zero value provided!");
        _tFrom(getContract(_ticker,false), _amount);
        uint _marketPrice = _getPr(_ticker);
        uint _getAmount = _getAmount(_marketPrice, _amount, false);
        require(_bd(address(this)) >= _getAmount, "No fund to execute the trade");
        _trd(_getAmount, msg.sender);
        emit Bought(_marketPrice, _amount, getAmount, _ticker, false, block.timestamp);
    }

    function exchangeDefault(string memory _ticker) external{
        uint _amount = msg.value;
        require(_amount > 0, "Zero value provided!");
        uint _marketPrice = _getPr(_ticker);
        uint _getAmount = _getAmount(_marketPrice, _amount, true);
        require(_bOf(getContract(_ticker,false), address(this)) >= _getAmount, "No fund to execute the trade");
         _tr(getAmount, msg.sender, getContract(_ticker, false));
          emit Bought(_marketPrice, _amount, getAmount, _ticker, true, block.timestamp); 
    }

}