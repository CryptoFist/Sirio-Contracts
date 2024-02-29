// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./HederaTokenService.sol";

interface ISFProtocolToken {
    struct FeeRate {
        uint16 borrowingFeeRate;
        uint16 redeemingFeeRate; 
        uint16 claimingFeeRate;
    }

    /// @notice Container for borrow balance information
    /// @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
    /// @member interestIndex Global borrowIndex as of the most recent balance-changing action
    struct BorrowSnapshot {
        uint principal;
        uint interestIndex;
    }

    struct SupplySnapshot {
        uint256 principal;
        uint256 claimed;
    }

    /// @notice The address of marketPositionManager.
    function marketPositionManager() external view returns (address);

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

    /// @notice Get exchangeRate.
    function getExchangeRateStored() external view returns (uint256);

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

    /// @notice Claim interests.
    function claimInterests(uint256 amount) external;

    /// @notice Repay borrowed underlying assets and get back SF token(shares).
    /// @param _repayAmount The amount of underlying assets to repay.
    function repayBorrow(uint256 _repayAmount) external;

    /// @notice Sender repays a borrow belonging to borrower
    /// @param _borrower the account with the debt being payed off
    /// @param _repayAmount The amount to repay, or -1 for the full outstanding amount
    function repayBorrowBehalf(
        address _borrower,
        uint256 _repayAmount
    ) external;

    /// @notice Liquidate borrowed underlying assets instead of borrower.
    /// @param _borrower The address of borrower.
    /// @param _borrowedToken The address of borrowed.
    /// @param _repayAmount The amount of underlying assert to liquidate.
    function liquidateBorrow(
        address _liquidator,
        address _borrower,
        address _borrowedToken,
        uint256 _repayAmount
    ) external;

    /// @notice Transfers collateral tokens (this market) to the liquidator.
    /// @dev Will fail unless called by another cToken during the process of liquidation.
    ///  Its absolutely critical to use msg.sender as the borrowed cToken and not a parameter.
    /// @param _liquidator The account receiving seized collateral
    /// @param _borrower The account having collateral seized
    /// @param _seizeTokens The number of cTokens to seize
    function seize(
        address _liquidator,
        address _borrower,
        uint256 _seizeTokens
    ) external;

    /// @notice seizeToprotocol seize asset to protocol.
    /// @param _borrower The address of borrower.
    /// @param _amount The amount of asset to seize.
    function seizeToprotocol(
        address _borrower,
        uint256 _amount
    ) external;

    /// @notice Sweep tokens.
    /// @dev Only owner can call this function and tokes will send to owner.
    /// @param _token The address of token to sweep.
    function sweepToken(address _token) external;

    /// @notice Get supplied underlying token amount of an user.
    function getSuppliedAmount(
        address _account
    ) external view returns (uint256);

    /// @notice Returns the current per-block borrow interest rate for this cToken
    /// @return The supply interest rate per block, scaled by 1e18
    function borrowRatePerBlock() external view returns (uint256);

    /// @notice Returns the current per-block supply interest rate for this cToken
    /// @return The supply interest rate per block, scaled by 1e18
    function supplyRatePerBlock() external view returns (uint256);

    /// @notice Convert amount of underlying token to share amount.
    function convertUnderlyingToShare(
        uint256 _amount
    ) external view returns (uint256);

    /// @notice Convert 18 decimals amount to underlying.
    function convertToUnderlying(
        uint256 _amount
    ) external view returns (uint256);

    /// @notice Pause contract when critical error occurs.
    /// @dev Only owner can call this function.
    function pause() external;

    /// @notice Unpause contract after fixed errors.
    /// @dev Only owner can call this function.
    function unpause() external;

    event InterestAccrued();

    event InterestsClaimed(address supplier, uint256 claimedAmount);

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

    event RepayBorrow(
        address payer,
        address borrower,
        uint repayAmount,
        uint accountBorrows,
        uint totalBorrows
    );

    event ReservesAdded(
        address benefactor,
        uint addAmount,
        uint newTotalReserves
    );

    event LiquidateBorrow(
        address liquidator,
        address borrower,
        uint repayAmount,
        address cTokenCollateral,
        address borrowedToken
    );
}

interface IInterestRateModel {
    /// @notice Update the parameters of the interest rate model (only callable by owner, i.e. Timelock)
    /// @param _baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
    /// @param _multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
    /// @param _jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
    /// @param _kink The utilization point at which the jump multiplier is applied
    function updateJumpRateModel(
        uint256 _baseRatePerYear,
        uint256 _multiplierPerYear,
        uint256 _jumpMultiplierPerYear,
        uint256 _kink
    ) external;

    /// @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
    /// @param _cash The amount of cash in the market
    /// @param _borrows The amount of borrows in the market
    /// @param _reserves The amount of reserves in the market (currently unused)
    /// @return The utilization rate as a mantissa between [0, 1e18]
    function utilizationRate(
        uint256 _cash,
        uint256 _borrows,
        uint256 _reserves
    ) external pure returns (uint256);

    /// @notice Updates the blocksPerYear in order to make interest calculations simpler
    /// @param _blocksPerYear The new estimated eth blocks per year.
    function updateBlocksPerYear(uint256 _blocksPerYear) external;

    /// @notice Calculates the current borrow rate per block, with the error code expected by the market
    /// @param _cash The amount of cash in the market
    /// @param _borrows The amount of borrows in the market
    /// @param _reserves The amount of reserves in the market
    /// @return The borrow rate percentage per block as a mantissa (scaled by 1e18)
    function getBorrowRate(
        uint256 _cash,
        uint256 _borrows,
        uint256 _reserves
    ) external view returns (uint256);

    /// @notice Calculates the current supply rate per block
    /// @param _cash The amount of cash in the market
    /// @param _borrows The amount of borrows in the market
    /// @param _reserves The amount of reserves in the market
    /// @param _reserveFactorMantissa The current reserve factor for the market
    /// @return The supply rate percentage per block as a mantissa (scaled by 1e18)
    function getSupplyRate(
        uint256 _cash,
        uint256 _borrows,
        uint256 _reserves,
        uint256 _reserveFactorMantissa
    ) external view returns (uint256);

    event NewInterestParams(
        uint256 baseRatePerBlock,
        uint256 multiplierPerBlock,
        uint256 jumpMultiplierPerBlock,
        uint256 kink
    );
}

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

    /// @notice Pause/Unpause borrowGuardian for tokens.
    /// @dev Only owner can call this function.
    function pauseBorrowGuardian(
        address[] memory _tokens,
        bool _pause
    ) external;

    /// @notice Pause/Unpause supplyGuardian for tokens.
    /// @dev Only owner can call this function.
    function pauseSupplyGuardian(
        address[] memory _tokens,
        bool _pause
    ) external;

    /// @notice Set borrow caps for tokens.
    /// @dev Only owner can call this function.
    function setBorrowCaps(
        address[] memory _tokens,
        uint256[] memory _borrowCaps
    ) external;

    /// @notice Set liquidateIncentiveMantissa.
    /// @dev Only owner can call this function.
    function setLiquidationIncentive(uint256 _liquidiateIncentive) external;

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

    /// @notice Get borrowable underlying token amount by a user.
    /// @param _account The address of borrower.
    /// @param _token The address of sfToken.
    function getBorrowableAmount(
        address _account,
        address _token
    ) external view returns (uint256);

    /// @notice Get liquidable amount with seize token.
    /// @param _borrowToken The address of borrowed sfToken.
    /// @param _seizeToken The address of sfToken to seize.
    /// @param _borrower The address of borrower.
    function getLiquidableAmountWithSeizeToken(
        address _borrowToken,
        address _seizeToken,
        address _borrower
    ) external view returns (uint256);

    /// @notice Get liquidable amount.
    /// @param _borrowToken The address of borrowed sfToken.
    /// @param _borrower The address of borrower.
    function getLiquidableAmount(
        address _borrowToken,
        address _borrower
    ) external view returns (uint256);

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
    /// @param _tokenSeize The address of token to be used as collateral.
    /// @param _borrower The address of the borrower.
    /// @param _liquidateAmount The amount of _tokenCollateral to liquidate.
    function validateLiquidate(
        address _tokenBorrowed,
        address _tokenSeize,
        address _borrower,
        uint256 _liquidateAmount
    ) external view;

    /// @notice Calculate number of tokens of collateral asset to seize given an underlying amount
    /// @param _borrowToken The address of the borrowed token
    /// @param _seizeToken The address of the collateral token
    /// @param _repayAmount The amount of sfTokenBorrowed underlying to convert into sfTokenCollateral tokens
    function liquidateCalculateSeizeTokens(
        address _borrowToken,
        address _seizeToken,
        uint256 _repayAmount
    ) external view returns (uint256);

    /// @notice Check if supplying is allowed and token is listed to market.
    function validateSupply(address _supplier, address _token) external;

    event NewMaxLiquidateRateSet(uint16 maxLiquidateRate);
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WHBAR() external pure returns (address);
    function whbar() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function addLiquidityNewPool(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external payable returns (uint amountA, uint amountB, uint liquidity);
    
    function addLiquidityETHNewPool(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

contract SFProtocolToken is
    ERC20,
    Ownable2Step,
    Pausable,
    ReentrancyGuard,
    ISFProtocolToken,
    HederaTokenService
{
    using SafeERC20 for IERC20;

    /// @notice Share amount per user.
    mapping(address => uint256) private accountBalance;

    /// @notice Borrowed underlying token amount per user.
    mapping(address => BorrowSnapshot) public accountBorrows;

    /// @notice Supplied underlying token amount per user.
    mapping(address => SupplySnapshot) public accountSupplies;

    /// @notice Information for feeRate.
    FeeRate public feeRate;

    /// @inheritdoc ISFProtocolToken
    address public override underlyingToken;

    ///@notice saucerswap router address
    address public swapRouter;

    /// @notice The address of interestRateModel contract.
    address public interestRateModel;

    /// @inheritdoc ISFProtocolToken
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
    

    constructor(
        FeeRate memory _feeRate,
        address _underlyingToken,
        address _interestRateModel,
        address _marketPositionManager,
        uint256 _initialExchangeRateMantissa,
        address _router,
        address _basetoken,
        string memory _name,
        string memory _symbol
    )  ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_underlyingToken != address(0), "invalid underlying token");
        require(
            _initialExchangeRateMantissa > 0,
            "invalid initialExchangeRateMantissa"
        );
        require(
            _marketPositionManager != address(0),
            "invalid marketPositionManager address"
        );

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

    modifier onlyManager{
        require(msg.sender == marketPositionManager, "caller is not manager");
        _;
    }

    /// @notice ERC20 standard function
    function balanceOf(
        address _account
    ) public view virtual override returns (uint256) {
        return accountBalance[_account];
    }

    function tokenAssociate(address tokenId) external {
       int response = HederaTokenService.associateToken(address(this), tokenId);
 
       if (response != HederaResponseCodes.SUCCESS) {
           revert ("Associate Failed");
       }
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
    function claimInterests(uint256 amount) external override {
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

        claimUnderlyingAmount = convertUnderlyingToShare(
            amount
        );
        claimShareAmount = (claimUnderlyingAmount * 1e18) / exchangeRate;

        totalClaimed += amount;
        supplySnapshot.claimed += amount;
        _totalSupply -= claimShareAmount;
        accountBalance[claimer] -= claimShareAmount;

        _doTransferOutWithFee(
            claimer,
            amount,
            feeRate.claimingFeeRate
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
        uint256 shareAmount = ( _seizeAmount * 1e18 )/ exchangeRate;
        uint256 underlyingAmount = convertToUnderlying(_seizeAmount);
        require(accountBalance[_borrower] >= shareAmount, "invalid balance");
        accountBalance[_borrower] -= shareAmount;
        accountBalance[_liquidator] += shareAmount;
        accountSupplies[_borrower].principal = accountSupplies[_borrower].principal >= underlyingAmount ? accountSupplies[_borrower].principal - underlyingAmount : 0;
        accountSupplies[_liquidator].principal += underlyingAmount;
        emit Transfer(_borrower, _liquidator, shareAmount);
    }

    /// @inheritdoc ISFProtocolToken
    function seizeToprotocol(
        address _borrower,
        uint256 _seizeAmount
    ) external override nonReentrant onlyManager {
        uint256 exchangeRate = _exchangeRateStoredInternal(
            totalBorrows,
            totalReserves
        );
        uint256 shareAmount = ( _seizeAmount * 1e18 )/ exchangeRate;
        uint256 underlyingAmount = convertToUnderlying(_seizeAmount);
        totalReserves += _seizeAmount;
        require(_totalSupply >= shareAmount, "invalid seize amount");
        _totalSupply = _totalSupply - shareAmount;
        accountBalance[_borrower] -= shareAmount;
        accountSupplies[_borrower].principal = accountSupplies[_borrower].principal >= underlyingAmount ? accountSupplies[_borrower].principal - underlyingAmount : 0;
        emit Transfer(_borrower, address(this), shareAmount);
        emit ReservesAdded(
            address(this),
            _seizeAmount,
            totalReserves
        );
    }

    /// @inheritdoc ISFProtocolToken
    function liquidateBorrow(
        address _liquidator,
        address _borrower,
        address _borrowedToken,
        uint256 _repayAmount
    ) external override onlyManager {
        require(_repayAmount > 0, "invalid liquidate amount");
        uint256 liquidatorBalance = getSuppliedAmount(_liquidator);
        if(_borrowedToken == address(this)){
            _accrueInterest();
            ( , uint256 accountBorrowsPrior, ) = getAccountSnapshot(_borrower);
            // uint256 accountBorrowsPrior = _borrowBalanceStoredInternal(
            //     _borrower,
            //     borrowIndex
            // );
            require(accountBorrowsPrior >= _repayAmount, "liquidate amount can't be bigger than borrow amount");
            uint256 accountBorrowsNew = accountBorrowsPrior - _repayAmount;
            require(totalBorrows >= _repayAmount, "can't be bigger than total borrow");
            uint256 totalBorrowsNew = totalBorrows - _repayAmount;
            accountBorrows[_borrower].principal = accountBorrowsNew;
            accountBorrows[_borrower].interestIndex = borrowIndex;
            totalBorrows = totalBorrowsNew;
        }
        else{
            address token1 = underlyingToken;
            address token2 = ISFProtocolToken(_borrowedToken).underlyingToken();
            uint256 outputAmount = ISFProtocolToken(_borrowedToken).convertToUnderlying(_repayAmount);
            address[] memory path = new address[](2);
            path[0] = token1;
            path[1] = token2;
            uint256[] memory amounts = IUniswapV2Router01(swapRouter).getAmountsIn(
                outputAmount,
                path
            );
            require(amounts[1] == outputAmount, "invalid swap amount");
            IERC20(token1).approve(swapRouter, amounts[0]);
            require(amounts[0] <= liquidatorBalance, "liquidator don't have enough assets");
            uint256 beforeBalance = getUnderlyingBalance();
            uint256 deadline = block.timestamp + 1000;
            if(token2 == HBARaddress){
                IUniswapV2Router01(swapRouter).swapTokensForExactETH(outputAmount, (amounts[0]), path, _borrowedToken, deadline);
            }
            else{
                IUniswapV2Router01(swapRouter).swapTokensForExactTokens(outputAmount, (amounts[0]), path, _borrowedToken, deadline);
            }
            uint256 afterBalance = getUnderlyingBalance();
            _repayAmount = convertUnderlyingToShare(beforeBalance - afterBalance);
        }

        uint256 exchangeRate = _exchangeRateStoredInternal(
            totalBorrows,
            totalReserves
        );
        uint256 liquidateShareAmount = (_repayAmount * 1e18) / exchangeRate;
        uint256 liquidateUnderlyingAmount = convertToUnderlying(_repayAmount);
        require(liquidatorBalance >= liquidateUnderlyingAmount, "liquidator don't have enough assets");
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

    function removeBorrow(address _borrower, uint256 _amount) external onlyManager{
         _accrueInterest();
        ( , uint256 accountBorrowsPrior, ) = getAccountSnapshot(_borrower);
        uint256 accountBorrowsNew = accountBorrowsPrior < _amount ? 0 : accountBorrowsPrior - _amount;
        uint256 totalBorrowsNew = totalBorrows >= _amount ? (totalBorrows - _amount) : 0;
        totalReserves += accountBorrowsPrior >= _amount ? 0 : (_amount - accountBorrowsPrior);
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
        if(redeemUnderlyingAmount > accountSupplies[_redeemer].principal){
            uint256 interest = getClaimableInterests(_redeemer);
            accountSupplies[_redeemer].principal -= redeemUnderlyingAmount - interest;
        }
        else{
            accountSupplies[_redeemer].principal -= redeemUnderlyingAmount;
        }

        _doTransferOutWithFee(
            _redeemer,
            redeemUnderlyingAmount,
            feeRate.redeemingFeeRate
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
