// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.17;

interface ISFProtocolToken {
    struct FeeRate {
        uint16 borrowingFeeRate;
        uint16 redeemingFeeRate;
    }

    /// @notice Get the address of underlying.
    function underlyingToken() external view returns (address);

    /// @notice Get underlying balance of SFProtocol token.
    function getUnderlyingBalance() external view returns (uint256);

    /// @notice Allow/Block supplying underlying token.
    /// @dev Only owner can call this function.
    function allowSupplyUnderlyingToken(bool _allow) external;

    /// @notice Supply underlying assets to lending pool.
    /// @param _underlyingAmount The amount of underlying asset.
    function supplyUnderlying(uint256 _underlyingAmount) external;

    /// @notice Redeem underlying asset by burning SF token(shares).
    /// @param _shareAmount The amount of SF token(shares) for redeem.
    function redeem(uint256 _shareAmount) external;

    /// @notice Redeem exact underlying asset.
    /// @param _underlyingAmount The amount of underlying asset that want to redeem.
    function redeemExactUnderlying(uint256 _underlyingAmount) external;

    /// @notice Borrow underlying assets from lending pool.
    /// @param _underlyingAmount The amount of underlying to borrow.
    function borrow(uint256 _underlyingAmount) external;

    /// @notice Repay borrowed underlying assets and get back SF token(shares).
    /// @param _underlyingAmount The amount of underlying assets to repay.
    function repayBorrow(uint256 _underlyingAmount) external;

    /// @notice Liquidate borrowed underlying assets instead of borrower.
    /// @param _borrower The address of borrower.
    /// @param _underlyingAmount The amount of underlying assert to liquidate.
    function liquidateBorrow(
        address _borrower,
        uint256 _underlyingAmount
    ) external;

    /// @notice Sweep tokens.
    /// @dev Only owner can call this function and tokes will send to owner.
    /// @param _token The address of token to sweep.
    function sweepToken(address _token) external;

    event SupplyingUnderlyingTokenAllowed(bool allowed);

    event InterestAccrued(
        uint256 cashPrior,
        uint256 interestAccumulated,
        uint256 totalBorrows
    );

    event UnderlyingSupplied(
        address supplier,
        uint256 underlyingAmount,
        uint256 shareAmount
    );
}
