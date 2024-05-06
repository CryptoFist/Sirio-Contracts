pragma solidity ^0.8.0;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

contract PythOracle {
    IPyth pyth;

    constructor(address pythContract) {
        pyth = IPyth(pythContract);
    }

    function getPrice(
        bytes32 _pricePair
    ) public view returns (PythStructs.Price memory price) {
        return pyth.getPrice(_pricePair);
    }

    function getPriceAmount(bytes32 _pricePair) public view returns (uint) {
        PythStructs.Price memory pythPrice = pyth.getPrice(_pricePair);

        uint hbarPrice8Decimals = (uint(uint64(pythPrice.price)) * (10 ** 8)) /
            (10 ** uint8(uint32(-1 * pythPrice.expo)));

        return hbarPrice8Decimals;
    }

    function getPriceInDollar(bytes32 _pricePair) public view returns (uint) {
        PythStructs.Price memory pythPrice = pyth.getPrice(_pricePair);

        uint hbarPrice8Decimals = (uint(uint64(pythPrice.price))) /
            (10 ** uint8(uint32(-1 * pythPrice.expo)));

        return hbarPrice8Decimals;
    }
}
