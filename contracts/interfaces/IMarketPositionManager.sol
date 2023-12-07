// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.17;

interface IMarketPositionManager {
    /// @notice Show market information.
    /// @member accountMembership true/false = ever borrowed or not.
    /// @member isListed listed in market.
    struct MarketInfo {
        mapping(address => bool) accountMembership;
        bool isListed;
    }

    /// @notice Check if token is listed to market or not.
    function checkListedToken(address _token) external view returns (bool);

    /// @notice Check if seize is allowed.
    /// @param _collateralToken The address of token to be uses as collateral.
    /// @param _borrowToken The address of borrowed token.
    function validateSeize(
        address _collateralToken,
        address _borrowToken
    ) external view;

    /// @notice Check if available to borrow exact amount of underlying token.
    /// @param _token The address of SFProtocolToken.
    /// @param _borrower The address of borrower.
    /// @param _borrowAmount The amount of underlying token to borrow.
    function validateBorrow(
        address _token,
        address _borrower,
        uint256 _borrowAmount
    ) external returns (bool);

    /// @notice Check if available to redeem exact amount of underlying token.
    /// @param _token The address of SFProtocolToken.
    /// @param _redeemer The address of redeemer.
    /// @param _redeemAmount The amount of underlying token to redeem.
    function validateRedeem(
        address _token,
        address _redeemer,
        uint256 _redeemAmount
    ) external view returns (bool);

    /// @notice Check if available to liquidate.
    /// @param _tokenBorrowed The address of borrowed token.
    /// @param _tokenCollateral The address of token to be used as collateral.
    /// @param _borrower The address of the borrower.
    /// @param _liquidateAmount The amount of _tokenCollateral to liquidate.
    function validateLiquidate(
        address _tokenBorrowed,
        address _tokenCollateral,
        address _borrower,
        uint256 _liquidateAmount
    ) external view;

    /// @notice Calculate number of tokens of collateral asset to seize given an underlying amount
    /// @dev Used in liquidation (called in cToken.liquidateBorrowFresh)
    /// @param _borrowToken The address of the borrowed token
    /// @param _collateralToken The address of the collateral token
    /// @param _repayAmount The amount of cTokenBorrowed underlying to convert into cTokenCollateral tokens
    function liquidateCalculateSeizeTokens(
        address _borrowToken,
        address _collateralToken,
        uint256 _repayAmount
    ) external view returns (uint256);

    /// @notice Check if supplying is allowed and token is listed to market.
    function validateSupply(address _token) external view;
}
