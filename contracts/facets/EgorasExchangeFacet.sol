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
   mapping (bytes=>mapping (bool=>uint)) totalMarketLiquidity;
   mapping (address=>mapping (bytes=>mapping (bool=>uint))) userLiquidity;
   mapping (bytes=>uint) accumulatedFee;
   mapping (bytes=>uint) sysAccumulatedFee;
   address internal feeCollector;
   address internal coinAddress;
   uint internal fee; //0.3%
   uint internal sysCut;
   string internal feePriceTicker;
   struct Providers{
      address provider;
    }
   Providers[] providers;
   mapping(bytes => Providers[]) listOfProviders;
   mapping (bytes => mapping(address => bool)) alreadyAProvider;

   using SafeMath for uint;
   using SafeDecimalMath for uint;
   event Bought(uint _price, uint _amount, uint _value, string _ticker, bool _isBase, uint time);
   event liquidityAdded(address user, string _ticker, uint _amount, uint time);
   event Rewarded(address _provider, uint due, address _initiator, string _ticker, uint timestamp);
   event LiquidityRemoved(uint _due, bool isDefault, uint userLiquidity, address user, uint timestamp);
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

    function _tFrom(address _contract, uint _amount, address _recipient) internal{
        require(ERC20I(_contract).allowance(msg.sender, _recipient) >= _amount, "Non-sufficient funds");
        require(ERC20I(_contract).transferFrom(msg.sender, _recipient, _amount), "Fail to tranfer fund");
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

    function _getTick(string memory _ticker) internal view returns (bytes memory) {
        ORACLE p = ORACLE(address(this));
        return p.converter(_ticker);
    }

    function _getAmount(uint _marketPrice, uint _amount, bool _isBase) internal pure returns (uint) {
        return _isBase ? _amount.divideDecimal(_marketPrice) : _amount.multiplyDecimal(_marketPrice);
    }

    function getDefault(string memory _ticker, uint _amount) external{
        require(_amount > 0, "Zero value provided!");
        _tFrom(_getContract(_ticker,false), _amount, address(this));
        uint _marketPrice = _getPr(_ticker);
        uint getAmount = _getAmount(_marketPrice, _amount, false);
        require(_bd(address(this)) >= getAmount, "No fund to execute the trade");
        _trd(getAmount, msg.sender);
        _trF(getAmount, true, _ticker);
        _update(_ticker, getAmount, true, false);
        _update(_ticker, _amount, false, true);
        emit Bought(_marketPrice, _amount, getAmount, _ticker, false, block.timestamp);
    }

   

    function exchangeDefault(string memory _ticker) external payable{
        uint _amount = msg.value;
        require(_amount > 0, "Zero value provided!");
        uint _marketPrice = _getPr(_ticker);
        uint getAmount = _getAmount(_marketPrice, _amount, true);
        require(_bOf(_getContract(_ticker,false), address(this)) >= getAmount, "No fund to execute the trade");
        _tr(getAmount, msg.sender, _getContract(_ticker, false));
        _trF(getAmount, false, _ticker);
        _update(_ticker, getAmount, false, false);
        _update(_ticker, _amount, true, true);
        emit Bought(_marketPrice, _amount, getAmount, _ticker, true, block.timestamp); 
    }

    function crossExchange(string memory _from, string memory _to, uint _amount) external payable{
        require(_amount > 0, "Zero value provided!");
        _tFrom(_getContract(_from,false), _amount, address(this));
        uint _marketPrice = _getPr(_from);
        uint getAmount = _getAmount(_marketPrice, _amount, false);
        uint _finalMarketPrice = _getPr(_to);
        uint getFinalAmount = _getAmount(_finalMarketPrice, getAmount, true);
        require(_bOf(_getContract(_to,false), address(this)) >= getFinalAmount, "No fund to execute the trade");
         _tr(getFinalAmount, msg.sender, _getContract(_to, false));
        _trF(getFinalAmount, false, _to);

        //
        _update(_to, getFinalAmount, false, false);
        _update(_from, _amount, false, true);
        //
        emit Bought(_finalMarketPrice, _amount, getFinalAmount, _to, false, block.timestamp);
    }

    
  function _getFee(uint _fAmount, bool isGetDefault, string memory _cTicker) internal view returns (uint) {
      uint _feePrice = _getPr(feePriceTicker);
      uint _tickerPrice = _getPr(_cTicker);
      uint _getFeeAmount = _fAmount.multiplyDecimalRound(fee);
      uint convertToDefault = isGetDefault ? _getFeeAmount.divideDecimal(_feePrice) : _getAmount(_tickerPrice, _getFeeAmount, false).divideDecimal(_feePrice);
      return convertToDefault;
  }
  function addLiquidity(string memory _ticker, uint _amount) external{
      require(_amount > 0, "Zero value provided!");
      address _c = _getContract(_ticker,false);
      _tFrom(_c, _amount, address(this));
      require(recordIt(_ticker,_amount, false), "Recording failed!");
      emit liquidityAdded(msg.sender, _ticker, _amount, block.timestamp);
  }
  function addDefaultLiquidity(string memory _ticker) external payable{
      uint _amount = msg.value;
      require(_amount > 0, "Zero value provided!");
      require(recordIt(_ticker,_amount, true), "Recording failed!");
      emit liquidityAdded(msg.sender, _ticker, _amount, block.timestamp);
  }

  function recordIt(string memory _ticker, uint _amount, bool which) internal returns(bool){
      bytes memory __ticker = _getTick(_ticker);
      totalMarketLiquidity[__ticker][which] = totalMarketLiquidity[_getTick(_ticker)][which].add(_amount);
      userLiquidity[msg.sender][__ticker][which] = userLiquidity[msg.sender][__ticker][which].add(_amount);
      if(!alreadyAProvider[__ticker][msg.sender]){
              alreadyAProvider[__ticker][msg.sender] = true;
                listOfProviders[__ticker].push(Providers(msg.sender));
            }
      return true;
  }

  function _calReward(bytes memory ___ticker, uint __price, address _provider) internal view returns (uint, uint){
        uint totalCombineLiquidity = __price.multiplyDecimal(totalMarketLiquidity[___ticker][false]).add(totalMarketLiquidity[___ticker][true]);
        uint totalCombineUserLiquidity = __price.multiplyDecimal(userLiquidity[_provider][___ticker][false]).add(userLiquidity[_provider][___ticker][true]);
        uint share = totalCombineUserLiquidity.divideDecimal(totalCombineLiquidity);
        return (share.multiplyDecimal(accumulatedFee[___ticker]),totalCombineLiquidity);
  }
  function withdrawable(string memory _ticker, bool isDefault, address _provider) external view returns (uint) {
      bytes memory ___ticker = _getTick(_ticker);
       uint totalCombineTokenLiquidity = isDefault ? totalMarketLiquidity[___ticker][true] : totalMarketLiquidity[_getTick(_ticker)][false];
       uint totalCombineUserLiquidity = isDefault ? userLiquidity[_provider][___ticker][true] : userLiquidity[_provider][___ticker][false];
       uint poolshARE = totalCombineUserLiquidity.divideDecimal(totalCombineTokenLiquidity);
       return  poolshARE.multiplyDecimal(totalCombineTokenLiquidity);
  }
 function removeLiquidity(string memory _ticker, bool isDefault) external{
     bytes memory ___ticker = _getTick(_ticker);
     uint _due = this.withdrawable(_ticker, isDefault, msg.sender);
     isDefault ? _trd(_due, msg.sender) : _tr(_due, msg.sender, _getContract(_ticker, false));
     isDefault ? totalMarketLiquidity[___ticker][true].sub(userLiquidity[msg.sender][___ticker][true]) : totalMarketLiquidity[___ticker][false].sub(userLiquidity[msg.sender][___ticker][false]);
     isDefault ? userLiquidity[msg.sender][___ticker][true] = 0 : userLiquidity[msg.sender][___ticker][true] = 0;

     emit LiquidityRemoved(_due, isDefault, userLiquidity[msg.sender][___ticker][true], msg.sender, block.timestamp);
 }
    function _shareSingleFees(string memory _ticker) internal {
        uint __price = _getPr(_ticker);
        bytes memory ___ticker = _getTick(_ticker);
        for (uint256 i = 0; i < listOfProviders[___ticker].length; i++) {
            address _provider = listOfProviders[___ticker][i].provider;
            uint due;
            uint totalCombineLiquidity;
            (due, totalCombineLiquidity) = _calReward(___ticker, __price, _provider);
            require(accumulatedFee[___ticker] >= due, "No fees left for distribution!");
            _tr(due, _provider, coinAddress);
            emit Rewarded(_provider, due, msg.sender, _ticker, block.timestamp);
        }

        accumulatedFee[___ticker] = 0;
    }

    function shareSingleFees(string memory _ticker) external {
       _shareSingleFees(_ticker);
    }

    function shareMultipleFees(string[] calldata _tickers) external {
         for (uint256 i; i < _tickers.length; i++) {
             string memory _ticker = _tickers[i];
             if(accumulatedFee[_getTick(_ticker)] > 0){
                _shareSingleFees(_ticker);
             }
         }
    }

    function _trF(uint _amount, bool isGetDefault, string memory _ticker) internal {
         uint __getFee = _getFee( _amount, isGetDefault, _ticker);
         uint __getSysFee = __getFee.multiplyDecimal(sysCut);
         _tFrom(coinAddress, __getSysFee, feeCollector);
         uint ___sysFee = __getFee.sub(__getSysFee);
         _tFrom(coinAddress, ___sysFee, address(this));
         accumulatedFee[_getTick(_ticker)] = accumulatedFee[_getTick(_ticker)].add(___sysFee);
         sysAccumulatedFee[_getTick(_ticker)] = sysAccumulatedFee[_getTick(_ticker)].add(__getSysFee);
    }

    function _update(string memory _ticker, uint _amount, bool isDefault, bool isAdd) internal view {
        isAdd ? totalMarketLiquidity[_getTick(_ticker)][isDefault].add(_amount) : totalMarketLiquidity[_getTick(_ticker)][isDefault].sub(_amount); 
    }
    function initVars(address _coinAddress, address _feeCollector, uint _fee, uint _sysCut, string memory _feePriceTicker) external{
        coinAddress = _coinAddress;
        feeCollector = _feeCollector;
        fee = _fee;
        sysCut = _sysCut;
        _feePriceTicker = feePriceTicker;
    }
   
    function userLiquidityBalances(address _provider, string memory _ticker) external view returns (uint, uint){
        bytes memory ___ticker = _getTick(_ticker);
        return(userLiquidity[_provider][___ticker][true], userLiquidity[_provider][___ticker][false]);
    }


}