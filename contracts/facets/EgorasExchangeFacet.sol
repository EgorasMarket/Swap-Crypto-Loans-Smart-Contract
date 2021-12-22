// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;
pragma experimental ABIEncoderV2;
import "../libraries/LibDiamond.sol";
import "../libraries/SafeDecimalMath.sol";
import "../libraries/SafeMath.sol";

interface ORACLE {
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

interface ERC20I {
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
   using SafeMath for uint;
   using SafeDecimalMath for uint;
   event Bought(uint _price, uint _amount, uint _value, string _ticker, bool _isBase, uint time);
   event liquidityAdded(address user, string _ticker, uint _amount, uint time);
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
        require(ERC20I(_contract).allowance(msg.sender, address(this)) >= _amount, "Non-sufficient funds");
        require(ERC20I(_contract).transferFrom(msg.sender, address(this), _amount), "Fail to tranfer fund");
    }
    function _bOf(address _contract, address _rec) internal view returns(uint){
        return ERC20I(_contract).balanceOf(_rec);
    }
     function _bd(address _rec) internal view returns(uint){
        return _rec.balance;
    }
    function _tr(uint _amount, address _rec, address _contract) internal{
        require(ERC20I(_contract).transfer(_rec, _amount), "Fail to tranfer fund");
    }
    function _trd(uint _amount, address _rec) internal{
        payable(_rec).transfer(_amount);
    }
    
    function _getContract(string memory _ticker, bool _isBase) internal view returns (address) {
        LoanMeta memory l = this.getTickerMeta(_ticker);
        require(l.base != address(0) && l.asset != address(0), "Pair not found!");
        return _isBase ? l.base : l.asset;
    }
    function _getPr(string memory _ticker) internal view returns (uint) {
        ORACLE p = ORACLE(address(this));
        return p.price(_ticker);
    }
    function _getAmount(uint _marketPrice, uint _amount, bool _isBase) internal pure returns (uint) {
        return _isBase ? _amount.divideDecimal(_marketPrice) : _amount.multiplyDecimal(_marketPrice);
    }
    function exchange(string memory _ticker, uint _amount, bool _isBase) external{
        require(_amount > 0, "Zero value provided!");
        _tFrom(_getContract(_ticker,_isBase), _amount);
        uint _marketPrice = _getPr(_ticker);
        uint getAmount = _getAmount(_marketPrice, _amount, _isBase);
        require(_bOf(_getContract(_ticker,_isBase), address(this)) >= getAmount, "No fund to execute the trade");
        _tr(getAmount, msg.sender, _getContract(_ticker, !_isBase));
        emit Bought(_marketPrice, _amount, getAmount, _ticker, _isBase, block.timestamp); 
    }

    function getDefault(string memory _ticker, uint _amount) external{
        require(_amount > 0, "Zero value provided!");
        _tFrom(_getContract(_ticker,false), _amount);
        uint _marketPrice = _getPr(_ticker);
        uint getAmount = _getAmount(_marketPrice, _amount, false);
        require(_bd(address(this)) >= getAmount, "No fund to execute the trade");
        _trd(getAmount, msg.sender);
        emit Bought(_marketPrice, _amount, getAmount, _ticker, false, block.timestamp);
    }

   

    function exchangeDefault(string memory _ticker) external payable{
        uint _amount = msg.value;
        require(_amount > 0, "Zero value provided!");
        uint _marketPrice = _getPr(_ticker);
        uint getAmount = _getAmount(_marketPrice, _amount, true);
        require(_bOf(_getContract(_ticker,false), address(this)) >= getAmount, "No fund to execute the trade");
        _tr(getAmount, msg.sender, _getContract(_ticker, false));
        emit Bought(_marketPrice, _amount, getAmount, _ticker, true, block.timestamp); 
    }

    function crossExchange(string memory _from, string memory _to, uint _amount) external payable{
        require(_amount > 0, "Zero value provided!");
        _tFrom(_getContract(_from,false), _amount);
        uint _marketPrice = _getPr(_from);
        uint getAmount = _getAmount(_marketPrice, _amount, false);
        uint _finalMarketPrice = _getPr(_to);
        uint getFinalAmount = _getAmount(_finalMarketPrice, getAmount, true);
        require(_bOf(_getContract(_to,false), address(this)) >= getFinalAmount, "No fund to execute the trade");
         _tr(getFinalAmount, msg.sender, _getContract(_to, false));
        emit Bought(_finalMarketPrice, _amount, getFinalAmount, _to, false, block.timestamp);
    }
    
  function addLiquidity(string memory _ticker, uint _amount) external{
      require(_amount > 0, "Zero value provided!");
      address _c = _getContract(_ticker,false);
      _tFrom(_c, _amount);
      emit liquidityAdded(msg.sender, _ticker, _amount, block.timestamp);
  }
  function addDefaultLiquidity(string memory _ticker) external payable{
      uint _amount = msg.value;
      require(_amount > 0, "Zero value provided!");
      emit liquidityAdded(msg.sender, _ticker, _amount, block.timestamp);
  }

}