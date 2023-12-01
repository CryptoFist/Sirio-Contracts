// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.17;

interface IInterestRateModel {
    /// @notice Indicator that this is an InterestRateModel contract (for inspection)
    function isInterestRateModel() external view returns (bool);

    /// @notice Calculates the current borrow interest rate per block
    /// @param _cash The total amount of cash the market has
    /// @param _borrows The total amount of borrows the market has outstanding
    /// @param _reserves The total amount of reserves the market has
    /// @return The borrow rate per block (as a percentage, and scaled by 1e18)
    function getBorrowRate(
        uint256 _cash,
        uint256 _borrows,
        uint256 _reserves
    ) external view returns (uint256);

    /// @notice Calculates the current supply interest rate per block
    /// @param _cash The total amount of cash the market has
    /// @param _borrows The total amount of borrows the market has outstanding
    /// @param _reserves The total amount of reserves the market has
    /// @param _reserveFactorMantissa The current reserve factor the market has
    /// @return The supply rate per block (as a percentage, and scaled by 1e18)
    function getSupplyRate(
        uint256 _cash,
        uint256 _borrows,
        uint256 _reserves,
        uint256 _reserveFactorMantissa
    ) external view returns (uint256);
}
