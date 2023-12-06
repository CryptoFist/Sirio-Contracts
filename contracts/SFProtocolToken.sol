// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ISFProtocolToken.sol";
import "./interfaces/IInterestRateModel.sol";
import "./interfaces/IMarketPositionManager.sol";

contract SFProtocolToken is
    ERC20Upgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    ISFProtocolToken
{
    using SafeERC20 for IERC20;

    /// @notice Share amount per user.
    mapping(address => uint256) private accountBalance;

    /// @notice Borrowed underlying token amount per user.
    mapping(address => BorrowSnapshot) private accountBorrows;

    /// @notice Information for feeRate.
    FeeRate public feeRate;

    /// @inheritdoc ISFProtocolToken
    address public override underlyingToken;

    /// @notice The address of interestRateModel contract.
    address public interestRateModel;

    /// @notice The address of marketPositionManager.
    address public marketPositionManager;

    /// @notice The initialExchangeRate that will be applied for first time.
    uint256 private initialExchangeRateMantissa;

    /// @notice Block number that interest was last accrued at
    uint256 public accrualBlockNumber;

    /// @inheritdoc ISFProtocolToken
    uint256 public override totalBorrows;

    /// @notice Total amount of reserves of the underlying held in this market
    uint256 public totalReserves;

    /// @notice Maximum borrow rate that can ever be applied (.0005% / block)
    uint256 internal constant borrowRateMaxMantissa = 0.00004e16;

    /// @notice Fraction of interest currently set aside for reserves
    uint256 public reserveFactorMantissa;

    /// @notice Total share amounts
    uint256 public _totalSupply;

    /// @notice Accumulator of the total earned interest rate since the opening of the market
    uint256 public borrowIndex;

    /// @notice 100% = 10000
    uint16 public FEERATE_FIXED_POINT = 10_000;

    /// @notice Underlying Token Decimals
    uint8 private underlyingDecimals;

    function initialize(
        FeeRate memory _feeRate,
        address _underlyingToken,
        address _interestRateModel,
        address _marketPositionManager,
        uint256 _initialExchangeRateMantissa,
        string memory _name,
        string memory _symbol
    ) public {
        require(_underlyingToken != address(0), "invalid underlying token");
        require(
            _initialExchangeRateMantissa > 0,
            "invalid initialExchangeRateMantissa"
        );
        require(
            _marketPositionManager != address(0),
            "invalid marketPositionManager address"
        );

        feeRate = _feeRate;
        underlyingToken = _underlyingToken;
        interestRateModel = _interestRateModel;
        initialExchangeRateMantissa = _initialExchangeRateMantissa;
        accrualBlockNumber = block.number;
        underlyingDecimals = IERC20Metadata(underlyingToken).decimals();
        borrowIndex = 1e18;
        __ERC20_init(_name, _symbol);
        __Ownable2Step_init();
    }

    /// @notice ERC20 standard function
    function balanceOf(
        address _account
    ) public view virtual override returns (uint256) {
        return accountBalance[_account];
    }

    /// @inheritdoc ISFProtocolToken
    function getAccountSnapshot(
        address _account
    ) external view override returns (uint256, uint256, uint256) {
        return (
            accountBalance[_account],
            _borrowBalanceStoredInternal(_account),
            _exchangeRateStoredInternal()
        );
    }

    /// @inheritdoc ISFProtocolToken
    function getUnderlyingBalance() public view override returns (uint256) {
        return IERC20(underlyingToken).balanceOf(address(this));
    }

    /// @inheritdoc ISFProtocolToken
    function supplyUnderlying(
        uint256 _underlyingAmount
    ) external override whenNotPaused {
        IMarketPositionManager(marketPositionManager).validateSupply(
            address(this)
        );

        _accrueInterest();

        uint256 exchangeRate = _exchangeRateStoredInternal();
        uint256 actualSuppliedAmount = _doTransferIn(
            msg.sender,
            _underlyingAmount
        );

        actualSuppliedAmount = _convertUnderlyingToShare(actualSuppliedAmount);
        uint256 shareAmount = (actualSuppliedAmount * 1e18) / exchangeRate;
        require(shareAmount > 0, "too small for supplying");

        _totalSupply += shareAmount;
        accountBalance[msg.sender] += shareAmount;

        emit UnderlyingSupplied(msg.sender, _underlyingAmount, shareAmount);
    }

    /// @inheritdoc ISFProtocolToken
    function redeem(uint256 _shareAmount) external override whenNotPaused {
        _redeem(msg.sender, _shareAmount, 0);
    }

    /// @inheritdoc ISFProtocolToken
    function redeemExactUnderlying(
        uint256 _underlyingAmount
    ) external override whenNotPaused {
        _redeem(msg.sender, 0, _underlyingAmount);
    }

    /// @inheritdoc ISFProtocolToken
    function borrow(uint256 _underlyingAmount) external override whenNotPaused {
        address borrower = msg.sender;
        IMarketPositionManager(marketPositionManager).validateBorrow(
            address(this),
            borrower,
            _underlyingAmount
        );

        _accrueInterest();

        require(
            getUnderlyingBalance() < _underlyingAmount,
            "insufficient pool amount to borrow"
        );

        uint256 accountBorrowsPrev = _borrowBalanceStoredInternal(borrower);
        uint256 accountBorrowsNew = accountBorrowsPrev + _underlyingAmount;
        uint256 totalBorrowsNew = totalBorrows + _underlyingAmount;

        accountBorrows[borrower].principal = accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrowsNew;

        _doTransferOutWithFee(
            borrower,
            _underlyingAmount,
            feeRate.borrowingFeeRate
        );

        emit Borrow(
            borrower,
            _underlyingAmount,
            accountBorrowsNew,
            totalBorrows
        );
    }

    /// @inheritdoc ISFProtocolToken
    function repayBorrow(uint256 _underlyingAmount) external override {}

    /// @inheritdoc ISFProtocolToken
    function liquidateBorrow(
        address _borrower,
        uint256 _underlyingAmount
    ) external override {}

    /// @inheritdoc ISFProtocolToken
    function pause() external override onlyOwner whenNotPaused {
        _pause();
    }

    /// @inheritdoc ISFProtocolToken
    function unpause() external override onlyOwner whenPaused {
        _unpause();
    }

    /// @inheritdoc ISFProtocolToken
    function sweepToken(address _token) external override {}

    /// @notice Applies accrued interest to total borrows and reserves
    /// @dev This calculates interest accrued from the last checkpointed block
    ///      up to the current block and writes new checkpoint to storage.
    function _accrueInterest() internal {
        uint256 curBlockNumber = block.number;
        if (accrualBlockNumber == curBlockNumber) return;

        uint256 cashPrior = getUnderlyingBalance();
        uint256 borrowsPrior = totalBorrows;
        uint256 reservesPrior = totalReserves;
        uint256 borrowIndexPrior = borrowIndex;

        // totalBorrows and totalReserves's decimal are 18.
        // Convert cashBal to 18 decimals and calculate borrowRate.
        uint256 borrowRate = IInterestRateModel(interestRateModel)
            .getBorrowRate(
                _convertUnderlyingToShare(cashPrior),
                borrowsPrior,
                reservesPrior
            );
        require(borrowRate <= borrowRateMaxMantissa, "borrow rate is too high");

        uint256 blockDelta = curBlockNumber - accrualBlockNumber;
        uint256 simpleInterestFactor = borrowRate * blockDelta;
        uint256 accumulatedInterests = (simpleInterestFactor * totalBorrows) /
            1e18;
        uint256 totalBorrowsNew = totalBorrows + accumulatedInterests;
        uint256 totalReservesNew = (accumulatedInterests * reservesPrior) +
            totalReserves;
        uint256 borrowIndexNew = (simpleInterestFactor * borrowIndexPrior) /
            1e18 +
            borrowIndexPrior;

        accrualBlockNumber = curBlockNumber;
        totalBorrows = totalBorrowsNew;
        totalReserves = totalReservesNew;
        borrowIndex = borrowIndexNew;

        emit InterestAccrued(cashPrior, accumulatedInterests, totalBorrowsNew);
    }

    /// @notice Redeem undnerlying token as exact underlying or with shares.
    function _redeem(
        address _redeemer,
        uint256 _shareAmount,
        uint256 _underlyingAmount
    ) internal {
        require(_shareAmount != 0 || _underlyingAmount != 0, "invalid amount");
        _accrueInterest();
        uint256 exchangeRate = _exchangeRateStoredInternal();

        uint256 redeemUnderlyingAmount = 0;
        uint256 redeemShareAmount = 0;

        // To get exact amount, underlyingAmount and shareAmount decimals should be 18.
        if (_shareAmount > 0) {
            // redeem with shares
            redeemShareAmount = _shareAmount;
            redeemUnderlyingAmount = (redeemShareAmount * exchangeRate) / 1e18;
        } else {
            // wanna redeem exact underlying tokens
            redeemUnderlyingAmount = _convertUnderlyingToShare(
                _underlyingAmount
            );
            redeemShareAmount = (redeemUnderlyingAmount * 1e18) / exchangeRate;
        }

        redeemUnderlyingAmount = _convertToUnderlying(redeemUnderlyingAmount);

        require(
            getUnderlyingBalance() >= redeemUnderlyingAmount,
            "insufficient pool"
        );
        require(
            accountBalance[_redeemer] >= redeemShareAmount,
            "insuffficient shares"
        );

        IMarketPositionManager(marketPositionManager).validateRedeem(
            address(this),
            _redeemer,
            redeemUnderlyingAmount
        );

        _totalSupply -= redeemShareAmount;
        accountBalance[_redeemer] -= redeemShareAmount;

        _doTransferOutWithFee(
            _redeemer,
            redeemUnderlyingAmount,
            feeRate.redeemingFeeRate
        );
    }

    /// @notice Caculate ExchangeRate
    /// @dev totalSuppliedAmount = totalAssetAmountInPool + totalBorrows - totalReserves
    /// @dev exchageRate = totalSuppliedAmount / totalShareAmount
    function _exchangeRateStoredInternal()
        internal
        view
        virtual
        returns (uint256)
    {
        if (_totalSupply == 0) {
            // If there are no tokens minted: exchangeRate = initialExchangeRate
            return initialExchangeRateMantissa;
        } else {
            // Otherwise: exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
            uint256 totalCash = getUnderlyingBalance();

            // totalBorrows and totalReserves are 18 decimals, convert cash decimal to 18.
            totalCash = _convertUnderlyingToShare(totalCash);
            uint256 cashPlusBorrowsMinusReserves = totalCash +
                totalBorrows -
                totalReserves;
            uint256 exchangeRate = (cashPlusBorrowsMinusReserves * 1e18) /
                _totalSupply;

            return exchangeRate;
        }
    }

    /// @notice Convert amount of underlying token to share amount.
    function _convertUnderlyingToShare(
        uint256 _amount
    ) internal view returns (uint256) {
        if (underlyingDecimals > 18) {
            return _amount / (underlyingDecimals - 18);
        } else {
            return _amount * (18 - underlyingDecimals);
        }
    }

    /// @notice Convert 18 decimals amount to underlying.
    function _convertToUnderlying(
        uint256 _amount
    ) internal view returns (uint256) {
        if (underlyingDecimals < 18) {
            return _amount / (18 - underlyingDecimals);
        } else {
            return _amount * (underlyingDecimals - 18);
        }
    }

    /// @notice Calculate actual transferred token amount.
    function _doTransferIn(
        address _from,
        uint256 _amount
    ) internal returns (uint256) {
        IERC20 token = IERC20(underlyingToken);
        uint balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(_from, address(this), _amount);
        uint balanceAfter = token.balanceOf(address(this));
        return balanceAfter - balanceBefore;
    }

    /// @notice Transfer underlyingToken to a user excluding fee.
    /// @dev Fee sends to owner.
    function _doTransferOutWithFee(
        address _to,
        uint256 _amount,
        uint16 _feeRate
    ) internal {
        uint256 feeAmount = (_amount * _feeRate) / FEERATE_FIXED_POINT;
        uint256 transferAmount = _amount - feeAmount;

        if (feeAmount > 0) {
            IERC20(underlyingToken).safeTransfer(owner(), feeAmount);
        }

        IERC20(underlyingToken).safeTransfer(_to, transferAmount);
    }

    /// @notice Return the borrow balance of account based on stored data.
    /// @param _account The address whose balance should be calculated.
    /// @return The calculated balance.
    function _borrowBalanceStoredInternal(
        address _account
    ) internal view returns (uint256) {
        BorrowSnapshot memory borrowSnapshot = accountBorrows[_account];

        if (borrowSnapshot.principal == 0) {
            return 0;
        }

        // Calculate new borrow balance using the interest index:
        // recentBorrowBalance = borrower.borrowBalance * market.borrowIndex / borrower.borrowIndex
        uint256 principalTimesIndex = borrowSnapshot.principal * borrowIndex;
        return principalTimesIndex / borrowSnapshot.interestIndex;
    }
}
