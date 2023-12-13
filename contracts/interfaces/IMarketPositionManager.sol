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

    /// @notice Set new PriceOracle contract address.
    /// @dev Only owner can call this function.
    function setPriceOracle(address _priceOracle) external;

    /// @notice Set new MaxLiquidateRate.
    /// @dev Only owner can call this function.
    function setMaxLiquidateRate(uint16 _newMaxLiquidateRate) external;

    /// @notice Add sfToken to markets.
    /// @dev Only owner can call this function.
    /// @param _token The address of sfToken to add to markets.
    function addToMarket(address _token) external;

    /// @notice Returns whether the given account is entered in the given asset
    /// @param _account The address of the account to check
    /// @param _token The sfToken to check
    /// @return True if the account is in the asset, otherwise false.
    function checkMembership(
        address _account,
        address _token
    ) external view returns (bool);

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
    /// @param _borrowToken The address of the borrowed token
    /// @param _collateralToken The address of the collateral token
    /// @param _repayAmount The amount of sfTokenBorrowed underlying to convert into sfTokenCollateral tokens
    function liquidateCalculateSeizeTokens(
        address _borrowToken,
        address _collateralToken,
        uint256 _repayAmount
    ) external view returns (uint256);

    /// @notice Check if supplying is allowed and token is listed to market.
    function validateSupply(address _token) external view;

    event NewMaxLiquidateRateSet(uint16 maxLiquidateRate);
}
