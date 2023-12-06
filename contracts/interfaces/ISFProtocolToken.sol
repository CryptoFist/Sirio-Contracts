// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.17;

interface ISFProtocolToken {
    struct FeeRate {
        uint16 borrowingFeeRate;
        uint16 redeemingFeeRate;
    }

    /// @notice Container for borrow balance information
    /// @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
    /// @member interestIndex Global borrowIndex as of the most recent balance-changing action
    struct BorrowSnapshot {
        uint principal;
        uint interestIndex;
    }

    /// @notice Get the address of underlying.
    function underlyingToken() external view returns (address);

    /// @notice Total amount of outstanding borrows of the underlying in this market
    function totalBorrows() external view returns (uint256);

    /// @notice Get underlying balance of SFProtocol token.
    function getUnderlyingBalance() external view returns (uint256);

    /// @notice Get account's shareBalance, borrowedAmount and exchangeRate.
    function getAccountSnapshot(
        address _account
    ) external view returns (uint256, uint256, uint256);

    /// @notice Supply underlying assets to lending pool.
    /// @dev Reverts when contract is paused.
    /// @param _underlyingAmount The amount of underlying asset.
    function supplyUnderlying(uint256 _underlyingAmount) external;

    /// @notice Redeem underlying asset by burning SF token(shares).
    /// @dev Reverts when contract is paused.
    /// @param _shareAmount The amount of SF token(shares) for redeem.
    function redeem(uint256 _shareAmount) external;

    /// @notice Redeem exact underlying asset.
    /// @dev Reverts when contract is paused.
    /// @param _underlyingAmount The amount of underlying asset that want to redeem.
    function redeemExactUnderlying(uint256 _underlyingAmount) external;

    /// @notice Borrow underlying assets from lending pool.
    /// @dev Reverts when contract is paused.
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

    /// @notice Pause contract when critical error occurs.
    /// @dev Only owner can call this function.
    function pause() external;

    /// @notice Unpause contract after fixed errors.
    /// @dev Only owner can call this function.
    function unpause() external;

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

    event Borrow(
        address borrower,
        uint borrowAmount,
        uint accountBorrows,
        uint totalBorrows
    );
}
