// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IPriceOracle.sol";

interface IToken {
    function decimals() external view returns (uint8);
}

contract PriceOracle is Ownable2Step, IPriceOracle {
    address public baseToken;

    address public swapRouter;

    address public factory;

    bool public constant isPriceOracle = true;

    constructor(address _baseToken, address _swapRouter) {
        baseToken = _baseToken;
        swapRouter = _swapRouter;
        factory = IUniswapV2Router02(swapRouter).factory();
        _transferOwnership(msg.sender);
    }

    function updateBaseToken(address _baseToken) external onlyOwner {
        require(_baseToken != address(0), "invalid baseToken address");
        baseToken = _baseToken;
    }

    function getUnderlyingPrice(
        address _token
    ) external view returns (uint256) {
        address pairAddress = IUniswapV2Factory(factory).getPair(
            baseToken,
            _token
        );
        if (pairAddress == address(0)) {
            return 0;
        }

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pairAddress)
            .getReserves();

        address token0 = IUniswapV2Pair(pairAddress).token0();

        uint256 baseReserve = token0 == baseToken ? reserve0 : reserve1;
        uint256 tokenReserve = token0 == _token ? reserve0 : reserve1;

        uint8 baseDecimal = IToken(baseToken).decimals();
        uint8 tokenDecimal = IToken(_token).decimals();

        baseReserve = _scaleTo(baseReserve, baseDecimal, 18);
        tokenReserve = _scaleTo(tokenReserve, tokenDecimal, 18);

        return (baseReserve * 1e18) / tokenReserve;
    }

    function _scaleTo(
        uint256 _amount,
        uint8 _fromDecimal,
        uint8 _toDecimal
    ) internal pure returns (uint256) {
        if (_fromDecimal < _toDecimal) {
            return _amount * 10 ** (_toDecimal - _fromDecimal);
        } else {
            return _amount / (10 ** (_fromDecimal - _toDecimal));
        }
    }
}
