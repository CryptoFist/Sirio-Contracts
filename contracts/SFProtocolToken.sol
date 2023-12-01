// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ISFProtocolToken.sol";

contract SFProtocolToken is
    ERC20Upgradeable,
    Ownable2StepUpgradeable,
    ISFProtocolToken
{
    using SafeERC20 for IERC20;

    /// @notice ERC20
    mapping(address => uint256) private accountBalance;

    /// @notice Information for feeRate.
    FeeRate public feeRate;

    /// @inheritdoc ISFProtocolToken
    address public override underlyingToken;

    /// @notice The address of interestRateModel contract.
    address public interestRateModel;

    /// @notice The initialExchangeRate that will be applied for first time.
    uint256 private initialExchangeRateMantissa;

    /// @notice 100% = 10000
    uint16 public FEERATE_FIXED_POINT = 10_000;

    /// @notice ERC20
    uint8 private _decimals;

    function initialize(
        FeeRate memory _feeRate,
        address _underlyingToken,
        address _interestRateModel,
        uint256 _initialExchangeRateMantissa,
        string memory _name,
        string memory _symbol,
        uint8 decimals_
    ) public {
        require(_underlyingToken != address(0), "invalid underlying token");

        feeRate = _feeRate;
        underlyingToken = _underlyingToken;
        interestRateModel = _interestRateModel;
        initialExchangeRateMantissa = _initialExchangeRateMantissa;
        _decimals = decimals_;
        __ERC20_init(_name, _symbol);
        __Ownable2Step_init();
    }

    /// @notice ERC20 standard function
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /// @notice ERC20 standard function
    function balanceOf(
        address _account
    ) public view virtual override returns (uint256) {
        return accountBalance[_account];
    }

    /// @inheritdoc ISFProtocolToken
    function getUnderlyingBalance() external view override returns (uint256) {}

    /// @inheritdoc ISFProtocolToken
    function supplyUnderlying(uint256 _underlyingAmount) external override {}

    /// @inheritdoc ISFProtocolToken
    function redeem(uint256 _shareAmount) external override {}

    /// @inheritdoc ISFProtocolToken
    function redeemExactUnderlying(
        uint256 _underlyingAmount
    ) external override {}

    /// @inheritdoc ISFProtocolToken
    function borrow(uint256 _underlyingAmount) external override {}

    /// @inheritdoc ISFProtocolToken
    function repayBorrow(uint256 _underlyingAmount) external override {}

    /// @inheritdoc ISFProtocolToken
    function liquidateBorrow(
        address _borrower,
        uint256 _underlyingAmount
    ) external override {}

    /// @inheritdoc ISFProtocolToken
    function sweepToken(address _token) external override {}
}
