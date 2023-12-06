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

    /// @notice Check if supplying is allowed and token is listed to market.
    function validateSupply(address _token) external view;
}
