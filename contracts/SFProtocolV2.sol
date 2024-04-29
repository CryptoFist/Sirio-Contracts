// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./HederaTokenService.sol";
import "./interfaces/ISFProtocolToken.sol";
import "./interfaces/IInterestRateModel.sol";
import "./interfaces/IMarketPositionManager.sol";
import "./interfaces/IUniswapV2Router.sol";


// dive into these toppics
// automated market maker
// price oracle
// TWAP
// slippage
// impermanent loss
// staking
// compounding

contract SFProtocolTokenV2 is
    ERC20,
    Ownable2Step,
    Pausable,
    ReentrancyGuard,
    ISFProtocolToken,
    HederaTokenService
{
    using SafeERC20 for IERC20;

    /// @notice interface for nft collection
    IERC721 public nftCollection;

    /// @notice Share amount per user. // clarify this one?
    mapping(address => uint256) private accountBalance;

    /// @notice Borrowed underlying token amount per user.
    mapping(address => BorrowSnapshot) public accountBorrows;

    /// @notice Supplied underlying token amount per user.
    mapping(address => SupplySnapshot) public accountSupplies;

    /// @notice Information for feeRate.
    FeeRate public feeRate;

    /// @inheritdoc ISFProtocolToken
    address public underlyingToken;

    ///@notice saucerswap router address
    address public swapRouter;

    /// @notice The address of interestRateModel contract.
    address public interestRateModel;

    address public marketPositionManager;

    /// @notice The initialExchangeRate that will be applied for first time.
    uint256 private initialExchangeRateMantissa;

    /// @notice Block number that interest was last accrued at
    uint256 public accrualBlockNumber;

    uint256 public totalBorrows;

    /// @notice Total amount of reserves of the underlying held in this market
    uint256 public totalReserves;

    /// @notice Maximum borrow rate that can ever be applied (.0005% / block)
    uint256 internal borrowRateMaxMantissa;

    /// @notice Fraction of interest currently set aside for reserves
    uint256 public reserveFactorMantissa;

    /// @notice Total share amounts
    uint256 public _totalSupply;

    /// @notice Accumulator of the total earned interest rate since the opening of the market
    uint256 public borrowIndex;

    /// @notice Share of seized collateral that is added to reserves
    uint256 public protocolSeizeShareMantissa;

    /// @notice Total claimed underlying token amount.
    uint256 public totalClaimed;

    /// @notice 100% = 10000
    uint16 public FEERATE_FIXED_POINT;

    /// @notice Underlying Token Decimals
    uint8 private underlyingDecimals;

    /// @notice wrapped HBAR token address
    address public HBARaddress;

    /**
     * @notice Constructor to create a new lending and borrowing market token
     * @param _feeRate Structure containing the fee rate for borrowing
     * @param _underlyingToken Address of the underlying token for the lending market
     * @param _interestRateModel Address of the interest rate model contract
     * @param _marketPositionManager Address of the market position manager
     * @param _initialExchangeRateMantissa Initial exchange rate used for calculating the initial amount of tokens minted
     * @param _router Address of the token swap router
     * @param _basetoken Address of the base token used in swap operations
     * @param _name ERC20 token name
     * @param _symbol ERC20 token symbol
     * @dev Sets up the initial state of the contract including constants and essential state variables. It checks for valid addresses and positive rate mantissa.
     */
    constructor(
        FeeRate memory _feeRate,
        address _underlyingToken,
        address _interestRateModel,
        address _marketPositionManager,
        address _nftCollection,
        uint256 _initialExchangeRateMantissa,
        address _router,
        address _basetoken,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_underlyingToken != address(0), "invalid underlying token");
        require(
            _initialExchangeRateMantissa > 0,
            "invalid initialExchangeRateMantissa"
        );
        require(
            _marketPositionManager != address(0),
            "invalid marketPositionManager address"
        );
        nftCollection = IERC721(_nftCollection);

        // set basic args
        borrowRateMaxMantissa = 0.00004e16;
        protocolSeizeShareMantissa = 2.8e16; //2.8%
        FEERATE_FIXED_POINT = 10000;

        feeRate = _feeRate;
        swapRouter = _router;
        HBARaddress = _basetoken;
        underlyingToken = _underlyingToken;
        interestRateModel = _interestRateModel;
        initialExchangeRateMantissa = _initialExchangeRateMantissa;
        accrualBlockNumber = block.number;
        underlyingDecimals = IERC20Metadata(underlyingToken).decimals();
        marketPositionManager = _marketPositionManager;
        borrowIndex = 1e18;
    }

    modifier onlyManager() {
        require(msg.sender == marketPositionManager, "caller is not manager");
        _;
    }

    /// @notice ERC20 standard function
    function balanceOf(
        address _account
    ) public view virtual override returns (uint256) {
        return accountBalance[_account];
    }

    function setFeeRate(FeeRate memory _feeRate) external onlyOwner {
        feeRate = _feeRate;
    }

    function setBorrowCaps(
        address[] memory _tokens,
        uint256[] memory _borrowCaps
    ) external onlyOwner {

    }

    function tokenAssociate(address tokenId) external {
        int response = HederaTokenService.associateToken(
            address(this),
            tokenId
        );

        if (response != HederaResponseCodes.SUCCESS) {
            revert("Associate Failed");
        }
    }

    /// @notice Retrieves comprehensive balance details for a specified user.
    /// @dev This function fetches and returns various types of balance information
    /// including borrow balance, supply principal, and claimable interests
    /// associated with the user's account.
    /// @param _user The address of the user whose balance information is being queried.
    /// @return borrowBalance The current borrow balance of the user.
    /// @return supplyPrincipal The principal supply balance of the user.
    /// @return claimableInterests The interests that the user can currently claim.
    function getAllBalances(address _user) external view returns(uint256 , uint256 , uint256) {
        (, uint256 borrowBalance, ) = getAccountSnapshot(_user);
        return (
            borrowBalance,
            accountSupplies[_user].principal,
            getClaimableInterests(_user)

        );
    }


    // account balance, getClaimbleInterest, look into get account snapshot

    /// @notice Calculates the fee discount based on the number of NFTs a user holds
    /// @dev Returns a reduced fee based on the number of NFTs the user holds
    /// @param _user The address of the user whose discount is to be calculated
    /// @param _baseFee The original fee rate, before any discounts are applied
    /// @return The adjusted fee after applying the discount for NFT ownership
    function checkNftDiscount(address _user, uint16 _baseFee) public view returns (uint16) {
        uint256 count = nftCollection.balanceOf(_user);
        
        if (count >= 4) {
            return 0; // 100% discount for 4 or more NFTs
        } else if (count == 3) {
            return _baseFee * 25 / 100; // 75% discount for 3 NFTs
        } else if (count == 2) {
            return _baseFee * 50 / 100; // 50% discount for 2 NFTs
        } else if (count == 1) {
            return _baseFee * 75 / 100; // 25% discount for 1 NFT
        }
        return _baseFee; // No discount if no NFTs are held
    }

    /// @inheritdoc ISFProtocolToken
    function supplyRatePerBlock() external view override returns (uint256) {
        (
            uint256 totalBorrowsNew,
            uint256 totalReservesNew,

        ) = getUpdatedRates();
        return
            IInterestRateModel(interestRateModel).getSupplyRate(
                convertUnderlyingToShare(getUnderlyingBalance()),
                totalBorrowsNew,
                totalReservesNew,
                reserveFactorMantissa
            );
    }

    /// @inheritdoc ISFProtocolToken
    function borrowRatePerBlock() external view override returns (uint256) {
        (
            uint256 totalBorrowsNew,
            uint256 totalReservesNew,

        ) = getUpdatedRates();
        return
            IInterestRateModel(interestRateModel).getBorrowRate(
                convertUnderlyingToShare(getUnderlyingBalance()),
                totalBorrowsNew,
                totalReservesNew
            );
    }

    /// @inheritdoc ISFProtocolToken
    function getSuppliedAmount(
        address _account
    ) public view override returns (uint256) {
        uint256 balance = accountBalance[_account];
        if (balance == 0) return 0;

        uint256 exchangeRate = getExchangeRateStored();
        uint256 suppliedAmount = (balance * exchangeRate) / 1e18;
        return convertToUnderlying(suppliedAmount);
    }

    /// @inheritdoc ISFProtocolToken
    function getExchangeRateStored() public view override returns (uint256) {
        (
            uint256 totalBorrowsNew,
            uint256 totalReservesNew,

        ) = getUpdatedRates();
        return _exchangeRateStoredInternal(totalBorrowsNew, totalReservesNew);
    }

    /// @inheritdoc ISFProtocolToken
    function getAccountSnapshot(
        address _account
    ) public view override returns (uint256, uint256, uint256) {
        (
            uint256 totalBorrowsNew,
            uint256 totalReservesNew,
            uint256 borrowIndexNew
        ) = getUpdatedRates();

        return (
            accountBalance[_account],
            _borrowBalanceStoredInternal(_account, borrowIndexNew),
            _exchangeRateStoredInternal(totalBorrowsNew, totalReservesNew)
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
        require(_underlyingAmount > 0, "invalid supply amount");
        IMarketPositionManager(marketPositionManager).validateSupply(
            msg.sender,
            address(this)
        );

        _accrueInterest();

        uint256 exchangeRate = _exchangeRateStoredInternal(
            totalBorrows,
            totalReserves
        );
        uint256 actualSuppliedAmount = _doTransferIn(
            msg.sender,
            _underlyingAmount
        );

        accountSupplies[msg.sender].principal += actualSuppliedAmount;

        actualSuppliedAmount = convertUnderlyingToShare(actualSuppliedAmount);
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
            getUnderlyingBalance() >= _underlyingAmount,
            "insufficient pool amount to borrow"
        );

        uint256 accountBorrowsPrev = _borrowBalanceStoredInternal(
            borrower,
            borrowIndex
        );
        uint256 accountBorrowsNew = accountBorrowsPrev +
            convertUnderlyingToShare(_underlyingAmount);
        uint256 totalBorrowsNew = totalBorrows +
            convertUnderlyingToShare(_underlyingAmount);

        accountBorrows[borrower].principal = accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrowsNew;


        uint16 fee = checkNftDiscount(borrower, feeRate.borrowingFeeRate);

        _doTransferOutWithFee(
            borrower,
            _underlyingAmount,
            fee
        );

        emit Borrow(
            borrower,
            _underlyingAmount,
            accountBorrowsNew,
            totalBorrows
        );
    }

    /// @notice Get claimableInterests amount.
    function getClaimableInterests(
        address _claimer
    ) public view returns (uint256) {
        SupplySnapshot memory supplySnapshot = accountSupplies[_claimer];
        uint256 suppliedAmount = supplySnapshot.principal;
        uint256 currentAmount = getSuppliedAmount(_claimer);
        uint256 claimableInterests = currentAmount - suppliedAmount;

        return claimableInterests;
    }

    /// @inheritdoc ISFProtocolToken
    function claimInterests(uint256 amount) external {
        address claimer = msg.sender;
        SupplySnapshot storage supplySnapshot = accountSupplies[claimer];
        uint256 claimableInterests = getClaimableInterests(claimer);
        require(claimableInterests >= amount, "not enough claimable interests");
        require(
            getUnderlyingBalance() >= amount,
            "not insufficient balance for interests"
        );

        uint256 claimUnderlyingAmount = 0;
        uint256 claimShareAmount = 0;
        _accrueInterest();
        uint256 exchangeRate = _exchangeRateStoredInternal(
            totalBorrows,
            totalReserves
        );

        claimUnderlyingAmount = convertUnderlyingToShare(amount);
        claimShareAmount = (claimUnderlyingAmount * 1e18) / exchangeRate;

        totalClaimed += amount;
        supplySnapshot.claimed += amount;
        _totalSupply -= claimShareAmount;
        accountBalance[claimer] -= claimShareAmount;

        uint16 fee = checkNftDiscount(claimer, feeRate.claimingFeeRate);

        _doTransferOutWithFee(
            claimer,
            amount,
            fee
        );
        
        emit InterestsClaimed(claimer, amount);
    }

    /// @inheritdoc ISFProtocolToken
    function repayBorrow(uint256 _repayAmount) external override {
        _repayBorrowInternal(msg.sender, msg.sender, _repayAmount);
    }

    /// @inheritdoc ISFProtocolToken
    function repayBorrowBehalf(
        address _borrower,
        uint256 _repayAmount
    ) external override {
        _repayBorrowInternal(msg.sender, _borrower, _repayAmount);
    }

    /// @inheritdoc ISFProtocolToken
    function seize(
        address _liquidator,
        address _borrower,
        uint256 _seizeAmount
    ) external override nonReentrant onlyManager {
        uint256 exchangeRate = _exchangeRateStoredInternal(
            totalBorrows,
            totalReserves
        );
        uint256 shareAmount = (_seizeAmount * 1e18) / exchangeRate;
        uint256 underlyingAmount = convertToUnderlying(_seizeAmount);
        require(accountBalance[_borrower] >= shareAmount, "invalid balance");
        accountBalance[_borrower] -= shareAmount;
        accountBalance[_liquidator] += shareAmount;
        accountSupplies[_borrower].principal = accountSupplies[_borrower]
            .principal >= underlyingAmount
            ? accountSupplies[_borrower].principal - underlyingAmount
            : 0;
        accountSupplies[_liquidator].principal += underlyingAmount;
        emit Transfer(_borrower, _liquidator, shareAmount);
    }

    /// @inheritdoc ISFProtocolToken
    function seizeToprotocol(
        address _borrower,
        uint256 _seizeAmount
    ) external nonReentrant onlyManager {
        uint256 exchangeRate = _exchangeRateStoredInternal(
            totalBorrows,
            totalReserves
        );
        uint256 shareAmount = (_seizeAmount * 1e18) / exchangeRate;
        uint256 underlyingAmount = convertToUnderlying(_seizeAmount);
        totalReserves += _seizeAmount;
        require(_totalSupply >= shareAmount, "invalid seize amount");
        _totalSupply = _totalSupply - shareAmount;
        accountBalance[_borrower] -= shareAmount;
        accountSupplies[_borrower].principal = accountSupplies[_borrower]
            .principal >= underlyingAmount
            ? accountSupplies[_borrower].principal - underlyingAmount
            : 0;
        emit Transfer(_borrower, address(this), shareAmount);
        emit ReservesAdded(address(this), _seizeAmount, totalReserves);
    }

    /// @inheritdoc ISFProtocolToken
    function liquidateBorrow(
        address _liquidator,
        address _borrower,
        address _borrowedToken,
        uint256 _repayAmount
    ) external onlyManager {
        require(_repayAmount > 0, "invalid liquidate amount");
        uint256 liquidatorBalance = getSuppliedAmount(_liquidator);
        if (_borrowedToken == address(this)) {
            _accrueInterest();
            (, uint256 accountBorrowsPrior, ) = getAccountSnapshot(_borrower);
            // uint256 accountBorrowsPrior = _borrowBalanceStoredInternal(
            //     _borrower,
            //     borrowIndex
            // );
            require(
                accountBorrowsPrior >= _repayAmount,
                "liquidate amount can't be bigger than borrow amount"
            );
            uint256 accountBorrowsNew = accountBorrowsPrior - _repayAmount;
            require(
                totalBorrows >= _repayAmount,
                "can't be bigger than total borrow"
            );
            uint256 totalBorrowsNew = totalBorrows - _repayAmount;
            accountBorrows[_borrower].principal = accountBorrowsNew;
            accountBorrows[_borrower].interestIndex = borrowIndex;
            totalBorrows = totalBorrowsNew;
        } else {
            address token1 = underlyingToken;
            address token2 = ISFProtocolToken(_borrowedToken).underlyingToken();
            uint256 outputAmount = ISFProtocolToken(_borrowedToken)
                .convertToUnderlying(_repayAmount);
            address[] memory path = new address[](2);
            path[0] = token1;
            path[1] = token2;
            uint256[] memory amounts = IUniswapV2Router01(swapRouter)
                .getAmountsIn(outputAmount, path);
            require(amounts[1] == outputAmount, "invalid swap amount");
            IERC20(token1).approve(swapRouter, amounts[0]);
            require(
                amounts[0] <= liquidatorBalance,
                "liquidator don't have enough assets"
            );
            uint256 beforeBalance = getUnderlyingBalance();
            uint256 deadline = block.timestamp + 1000;
            if (token2 == HBARaddress) {
                IUniswapV2Router01(swapRouter).swapTokensForExactETH(
                    outputAmount,
                    (amounts[0]),
                    path,
                    _borrowedToken,
                    deadline
                );
            } else {
                IUniswapV2Router01(swapRouter).swapTokensForExactTokens(
                    outputAmount,
                    (amounts[0]),
                    path,
                    _borrowedToken,
                    deadline
                );
            }
            uint256 afterBalance = getUnderlyingBalance();
            _repayAmount = convertUnderlyingToShare(
                beforeBalance - afterBalance
            );
        }

        uint256 exchangeRate = _exchangeRateStoredInternal(
            totalBorrows,
            totalReserves
        );
        uint256 liquidateShareAmount = (_repayAmount * 1e18) / exchangeRate;
        uint256 liquidateUnderlyingAmount = convertToUnderlying(_repayAmount);
        require(
            liquidatorBalance >= liquidateUnderlyingAmount,
            "liquidator don't have enough assets"
        );
        _totalSupply -= liquidateShareAmount;
        accountBalance[_liquidator] -= liquidateShareAmount;
        accountSupplies[_liquidator].principal -= liquidateUnderlyingAmount;

        emit LiquidateBorrow(
            _liquidator,
            _borrower,
            liquidateUnderlyingAmount,
            address(this),
            _borrowedToken
        );
    }

    function removeBorrow(
        address _borrower,
        uint256 _amount
    ) external onlyManager {
        _accrueInterest();
        (, uint256 accountBorrowsPrior, ) = getAccountSnapshot(_borrower);
        uint256 accountBorrowsNew = accountBorrowsPrior < _amount
            ? 0
            : accountBorrowsPrior - _amount;
        uint256 totalBorrowsNew = totalBorrows >= _amount
            ? (totalBorrows - _amount)
            : 0;
        totalReserves += accountBorrowsPrior >= _amount
            ? 0
            : (_amount - accountBorrowsPrior);
        accountBorrows[_borrower].principal = accountBorrowsNew;
        accountBorrows[_borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrowsNew;
    }

    /// @inheritdoc ISFProtocolToken
    function pause() external override onlyOwner whenNotPaused {
        _pause();
    }

    /// @inheritdoc ISFProtocolToken
    function unpause() external override onlyOwner whenPaused {
        _unpause();
    }

    /// @inheritdoc ISFProtocolToken
    function convertUnderlyingToShare(
        uint256 _amount
    ) public view override returns (uint256) {
        if (underlyingDecimals > 18) {
            return _amount / 10 ** (underlyingDecimals - 18);
        } else {
            return _amount * 10 ** (18 - underlyingDecimals);
        }
    }

    /// @inheritdoc ISFProtocolToken
    function convertToUnderlying(
        uint256 _amount
    ) public view override returns (uint256) {
        if (underlyingDecimals < 18) {
            return _amount / 10 ** (18 - underlyingDecimals);
        } else {
            return _amount * 10 ** (underlyingDecimals - 18);
        }
    }

    /// @inheritdoc ISFProtocolToken
    function sweepToken(address _token) external override onlyOwner {
        require(_token != underlyingToken, "can not sweep underlying token");
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(owner(), balance);
    }

    /// @notice Applies accrued interest to total borrows and reserves
    /// @dev This calculates interest accrued from the last checkpointed block
    ///      up to the current block and writes new checkpoint to storage.
    function _accrueInterest() internal {
        uint256 curBlockNumber = block.number;
        if (accrualBlockNumber == curBlockNumber) return;

        (
            uint256 totalBorrowsNew,
            uint256 totalReservesNew,
            uint256 borrowIndexNew
        ) = getUpdatedRates();

        accrualBlockNumber = curBlockNumber;
        totalBorrows = totalBorrowsNew;
        totalReserves = totalReservesNew;
        borrowIndex = borrowIndexNew;

        emit InterestAccrued();
    }

    /// @notice Payer repays a borrow belonging to borrower
    /// @param _payer The account to repay debt being payed off
    /// @param _borrower The account with the debt being payed off
    /// @param _repayAmount The amount to repay, or -1 for the full outstanding amount
    function _repayBorrowInternal(
        address _payer,
        address _borrower,
        uint256 _repayAmount
    ) internal returns (uint256) {
        _accrueInterest();
        IMarketPositionManager(marketPositionManager).checkListedToken(
            address(this)
        );

        uint256 accountBorrowsPrior = _borrowBalanceStoredInternal(
            _borrower,
            borrowIndex
        );
        uint256 repayAmountFinal = convertUnderlyingToShare(_repayAmount) >
            accountBorrowsPrior
            ? convertToUnderlying(accountBorrowsPrior)
            : _repayAmount;

        require(repayAmountFinal > 0, "no borrows to repay");

        uint256 actualRepayAmount = _doTransferIn(_payer, repayAmountFinal);
        actualRepayAmount = convertUnderlyingToShare(actualRepayAmount);
        uint256 accountBorrowsNew = accountBorrowsPrior - actualRepayAmount;
        uint256 totalBorrowsNew = totalBorrows - actualRepayAmount;

        accountBorrows[_borrower].principal = accountBorrowsNew;
        accountBorrows[_borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrowsNew;

        emit RepayBorrow(
            _payer,
            _borrower,
            actualRepayAmount,
            accountBorrowsNew,
            totalBorrowsNew
        );

        return actualRepayAmount;
    }

    /// @notice Redeem undnerlying token as exact underlying or with shares.
    function _redeem(
        address _redeemer,
        uint256 _shareAmount,
        uint256 _underlyingAmount
    ) internal {
        require(_shareAmount != 0 || _underlyingAmount != 0, "invalid amount");
        _accrueInterest();
        uint256 exchangeRate = _exchangeRateStoredInternal(
            totalBorrows,
            totalReserves
        );

        uint256 redeemUnderlyingAmount = 0;
        uint256 redeemShareAmount = 0;

        // To get exact amount, underlyingAmount and shareAmount decimals should be 18.
        if (_shareAmount > 0) {
            // redeem with shares
            redeemShareAmount = _shareAmount;
            redeemUnderlyingAmount = (redeemShareAmount * exchangeRate) / 1e18;
        } else {
            // wanna redeem exact underlying tokens
            redeemUnderlyingAmount = convertUnderlyingToShare(
                _underlyingAmount
            );
            redeemShareAmount = (redeemUnderlyingAmount * 1e18) / exchangeRate;
        }

        redeemUnderlyingAmount = convertToUnderlying(redeemUnderlyingAmount);

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
        if (redeemUnderlyingAmount > accountSupplies[_redeemer].principal) {
            uint256 interest = getClaimableInterests(_redeemer);
            accountSupplies[_redeemer].principal -=
                redeemUnderlyingAmount -
                interest;
        } else {
            accountSupplies[_redeemer].principal -= redeemUnderlyingAmount;
        }

        uint16 fee = checkNftDiscount(_redeemer, feeRate.redeemingFeeRate);

        _doTransferOutWithFee(
            _redeemer,
            redeemUnderlyingAmount,
            fee
        );
    }

    /// @notice Caculate ExchangeRate
    /// @dev totalSuppliedAmount = totalAssetAmountInPool + totalBorrows - totalReserves
    /// @dev exchageRate = totalSuppliedAmount / totalShareAmount
    function _exchangeRateStoredInternal(
        uint256 _totalBorrows,
        uint256 _totalReserves
    ) internal view virtual returns (uint256) {
        if (_totalSupply == 0) {
            // If there are no tokens minted: exchangeRate = initialExchangeRate
            return initialExchangeRateMantissa;
        } else {
            // Otherwise: exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
            uint256 totalCash = getUnderlyingBalance();

            // totalBorrows and totalReserves are 18 decimals, convert cash decimal to 18.
            totalCash = convertUnderlyingToShare(totalCash);
            uint256 cashPlusBorrowsMinusReserves = totalCash +
                _totalBorrows -
                _totalReserves;
            uint256 exchangeRate = (cashPlusBorrowsMinusReserves * 1e18) /
                _totalSupply;

            return exchangeRate;
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
        address _account,
        uint256 _borrowIndex
    ) internal view returns (uint256) {
        BorrowSnapshot memory borrowSnapshot = accountBorrows[_account];

        if (borrowSnapshot.principal == 0) {
            return 0;
        }

        // Calculate new borrow balance using the interest index:
        // recentBorrowBalance = borrower.borrowBalance * market.borrowIndex / borrower.borrowIndex
        uint256 principalTimesIndex = borrowSnapshot.principal * _borrowIndex;
        return principalTimesIndex / borrowSnapshot.interestIndex;
    }

    function getUpdatedRates()
        public
        view
        returns (
            uint256 totalBorrowsNew,
            uint256 totalReservesNew,
            uint256 borrowIndexNew
        )
    {
        uint256 curBlockNumber = block.number;

        if (curBlockNumber == accrualBlockNumber) {
            return (totalBorrows, totalReserves, borrowIndex);
        }

        uint256 cashPrior = getUnderlyingBalance();
        uint256 borrowsPrior = totalBorrows;
        uint256 reservesPrior = totalReserves;
        uint256 borrowIndexPrior = borrowIndex;

        uint256 borrowRate = IInterestRateModel(interestRateModel)
            .getBorrowRate(
                convertUnderlyingToShare(cashPrior),
                borrowsPrior,
                reservesPrior
            );

        uint256 blockDelta = curBlockNumber - accrualBlockNumber;
        uint256 simpleInterestFactor = borrowRate * blockDelta;
        uint256 accumulatedInterests = (simpleInterestFactor * totalBorrows) /
            1e18;
        totalBorrowsNew = totalBorrows + accumulatedInterests;
        totalReservesNew =
            (accumulatedInterests * reserveFactorMantissa) /
            1e18 +
            reservesPrior;
        borrowIndexNew =
            (simpleInterestFactor * borrowIndexPrior) /
            1e18 +
            borrowIndexPrior;
    }
}
