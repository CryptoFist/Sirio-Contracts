// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.17;

import "./interfaces/IInterestRateModel.sol";

contract InterestRateModel is IInterestRateModel {
    /// @inheritdoc IInterestRateModel
    bool public constant isInterestRateModel = true;

    constructor() {}

    /// @inheritdoc IInterestRateModel
    function getBorrowRate(
        uint256 _cash,
        uint256 _borrows,
        uint256 _reserves
    ) external view override returns (uint256) {}

    /// @inheritdoc IInterestRateModel
    function getSupplyRate(
        uint256 _cash,
        uint256 _borrows,
        uint256 _reserves,
        uint256 _reserveFactorMantissa
    ) external view override returns (uint256) {}
}
