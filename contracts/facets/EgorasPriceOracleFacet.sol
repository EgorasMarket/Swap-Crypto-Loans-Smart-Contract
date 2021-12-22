// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;
import "../libraries/LibDiamond.sol";


contract EgorasPriceOracleFacet
{  

    mapping (bytes=>uint) private ticker;
    mapping (address=>bool) private pythia;
    event PythiaAdded(address _pythia, address _addBy, uint _time);
    event PythiaSuspended(address _pythia, address _addBy, uint _time);
    event PriceUpdated(string _ticker, uint _price, address _pythia, uint _time);
    event PrinceChanged(uint _time);
    modifier onlyOwner{
        require(msg.sender == LibDiamond.contractOwner(), "Access denied, Only owner is allowed!");
        _;
    }

    modifier onlyPythia{
        require(pythia[msg.sender], "Access denied. Only Pythia is allowed!");
        _;
    }

  function updateTickerPrices(uint256[] calldata _prices, string[] calldata _tickers) external onlyPythia {
    require(_prices.length == _tickers.length, "Prices and tickers must be of equal length");
    for (uint256 i; i < _prices.length; i++) {
        ticker[this.converter(_tickers[i])] = _prices[i];
        emit PriceUpdated(_tickers[i], _prices[i], msg.sender, block.timestamp);
        }
        emit PrinceChanged(block.timestamp);

  }

  function price(string memory _ticker) external view returns(uint){
    return ticker[this.converter(_ticker)];
  }

  function setPythia(address _pythia) external onlyOwner{
    pythia[_pythia] = true;
    emit PythiaAdded(_pythia, msg.sender, block.timestamp);
  }

  function suspendPythia(address _pythia) external onlyOwner{
    pythia[_pythia] = false;
    emit PythiaSuspended(_pythia, msg.sender, block.timestamp);
  }
  function converter(string memory _source) external pure returns (bytes memory) {
    return bytes(upper(_source));
  }

  function upper(string memory _base)
        internal
        pure
        returns (string memory) {
        bytes memory _baseBytes = bytes(_base);
        for (uint i = 0; i < _baseBytes.length; i++) {
            _baseBytes[i] = _upper(_baseBytes[i]);
        }
        return string(_baseBytes);
    }
      function _upper(bytes1 _b1)
        private
        pure
        returns (bytes1) {

        if (_b1 >= 0x61 && _b1 <= 0x7A) {
            return bytes1(uint8(_b1) - 32);
        }

        return _b1;
    }
    }