// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPriceOracle {
    function isPriceOracle() external view returns (bool);

    function getUnderlyingPrice(address _token) external view returns (uint256);
}

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
    function claimInterests() external;

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
    /// @param _collateralToken The address of token to seize.
    /// @param _repayAmount The amount of underlying assert to liquidate.
    function liquidateBorrow(
        address _borrower,
        address _collateralToken,
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
        uint seizeTokens
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

contract MarketPositionManager is OwnableUpgradeable, IMarketPositionManager {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Reflect if borrow is allowed.
    mapping(address => bool) public borrowGuardianPaused;

    /// @notice Reflect if supply is allowed.
    mapping(address => bool) public supplyGuardianPaused;

    /// @notice Reflect market information.
    mapping(address => MarketInfo) private markets;

    /// @notice Limit amounts by each token.
    /// @dev 0 means unlimit borrow.
    mapping(address => uint256) public borrowCaps;

    /// @notice Assets array that a user borrowed.
    mapping(address => EnumerableSet.AddressSet) private accountAssets;

    /// @notice Multiplier representing the discount on collateral that a liquidator receives
    uint256 public liquidationIncentiveMantissa;

    /// @notice The max liquidate rate based on borrowed amount.
    uint16 public maxLiquidateRate;

    /// @notice 10,000 = 100%
    uint16 public constant FIXED_RATE = 10_000;

    uint256 public HBARprice;

    IPriceOracle public priceOracle;

    modifier onlyValidCaller(address _token) {
        require(msg.sender == _token, "invalid caller");
        require(markets[_token].isListed, "not listed token");
        _;
    }

    function initialize(
        address _priceOracle,
        uint16 _maxLiquidateRate
    ) public initializer {
        __Ownable_init();
        setPriceOracle(_priceOracle);
        setMaxLiquidateRate(_maxLiquidateRate);
        liquidationIncentiveMantissa = 1e18;
        HBARprice = 7000000;
    }

    /// @inheritdoc IMarketPositionManager
    function setPriceOracle(address _priceOracle) public override onlyOwner {
        require(
            _priceOracle != address(0),
            "invalid PriceOracle contract address"
        );
        priceOracle = IPriceOracle(_priceOracle);
    }

    /// @inheritdoc IMarketPositionManager
    function pauseBorrowGuardian(
        address[] memory _tokens,
        bool _pause
    ) external override onlyOwner {
        uint256 length = _tokens.length;
        require(length > 0, "invalid array length");
        for (uint256 i = 0; i < length; i++) {
            borrowGuardianPaused[_tokens[i]] = _pause;
        }
    }

    /// @inheritdoc IMarketPositionManager
    function pauseSupplyGuardian(
        address[] memory _tokens,
        bool _pause
    ) external override onlyOwner {
        uint256 length = _tokens.length;
        require(length > 0, "invalid arrray length");
        for (uint256 i = 0; i < length; i++) {
            supplyGuardianPaused[_tokens[i]] = _pause;
        }
    }

    /// @inheritdoc IMarketPositionManager
    function setBorrowCaps(
        address[] memory _tokens,
        uint256[] memory _borrowCaps
    ) external override onlyOwner {
        uint256 length = _tokens.length;
        require(
            length > 0 && length == _borrowCaps.length,
            "invalid array length"
        );
        for (uint256 i = 0; i < length; i++) {
            borrowCaps[_tokens[i]] = _borrowCaps[i];
        }
    }

    /// @inheritdoc IMarketPositionManager
    function setLiquidationIncentive(
        uint256 _liquidiateIncentive
    ) external override onlyOwner {
        liquidationIncentiveMantissa = _liquidiateIncentive;
    }

    /// @inheritdoc IMarketPositionManager
    function checkMembership(
        address _account,
        address _token
    ) external view override returns (bool) {
        return markets[_token].accountMembership[_account];
    }

    /// @inheritdoc IMarketPositionManager
    function setMaxLiquidateRate(
        uint16 _newMaxLiquidateRate
    ) public override onlyOwner {
        require(_newMaxLiquidateRate <= FIXED_RATE, "invalid maxLiquidateRate");
        maxLiquidateRate = _newMaxLiquidateRate;
        emit NewMaxLiquidateRateSet(_newMaxLiquidateRate);
    }

    /// @inheritdoc IMarketPositionManager
    function addToMarket(address _token) external override onlyOwner {
        MarketInfo storage info = markets[_token];
        require(!info.isListed, "already added");
        markets[_token].isListed = true;
    }

    function getAccountAssets(address account) external view returns (address[] memory) {
        return accountAssets[account].values();
    }

    /// @inheritdoc IMarketPositionManager
    function validateSupply(
        address _supplier,
        address _token
    ) external override onlyValidCaller(_token) {
        require(!supplyGuardianPaused[_token], "supplying is paused");
        if (!accountAssets[_supplier].contains(_token)) {
            accountAssets[_supplier].add(_token);
        }
    }

    /// @inheritdoc IMarketPositionManager
    function checkListedToken(
        address _token
    ) external view override returns (bool) {
        return markets[_token].isListed;
    }

    bool public seizeGuardianPaused;

    /// @inheritdoc IMarketPositionManager
    function validateSeize(
        address _seizeToken,
        address _borrowToken
    ) external view override {
        require(!seizeGuardianPaused, "seize is paused");
        require(
            markets[_seizeToken].isListed && markets[_borrowToken].isListed,
            "not listed token"
        );
        require(
            ISFProtocolToken(_seizeToken).marketPositionManager() ==
                ISFProtocolToken(_borrowToken).marketPositionManager(),
            "mismatched markeManagerPosition"
        );
    }

    /// @inheritdoc IMarketPositionManager
    function liquidateCalculateSeizeTokens(
        address _borrowToken,
        address _seizeToken,
        uint256 _repayAmount
    ) public view override returns (uint256) {
        uint256 borrowTokenPrice = priceOracle.getUnderlyingPrice(_borrowToken);
        uint256 seizeTokenPrice = priceOracle.getUnderlyingPrice(_seizeToken);

        require(borrowTokenPrice > 0 && seizeTokenPrice > 0, "price error");

        uint256 exchangeRate = ISFProtocolToken(_seizeToken)
            .getExchangeRateStored();

        uint256 borrowIncentive = liquidationIncentiveMantissa *
            borrowTokenPrice;
        uint256 collateralIncentive = seizeTokenPrice * exchangeRate;

        uint256 ratio = (borrowIncentive * 1e18) / collateralIncentive;
        uint256 seizeTokens = (ratio * _repayAmount) / 1e18;

        return seizeTokens;
    }

    /// @inheritdoc IMarketPositionManager
    function getLiquidableAmountWithSeizeToken(
        address _borrowToken,
        address _seizeToken,
        address _borrower
    ) external view override returns (uint256) {
        (, uint256 borrowAmount, ) = ISFProtocolToken(_borrowToken)
            .getAccountSnapshot(_borrower);
        if (!markets[_borrowToken].isListed || !markets[_seizeToken].isListed) {
            return 0;
        }

        uint256 liquidableAmount;
        if (borrowGuardianPaused[_borrowToken]) {
            liquidableAmount = borrowAmount;
        } else {
            bool validation = _checkValidation(_borrower, _borrowToken, 0, 0);
            liquidableAmount = validation
                ? 0
                : ((borrowAmount * maxLiquidateRate) / FIXED_RATE);
        }

        uint256 borrowTokenPrice = priceOracle.getUnderlyingPrice(_borrowToken);
        uint256 seizeTokenPrice = priceOracle.getUnderlyingPrice(_seizeToken);

        require(borrowTokenPrice > 0 && seizeTokenPrice > 0, "price error");

        uint256 exchangeRate = ISFProtocolToken(_seizeToken)
            .getExchangeRateStored();
        uint256 borrowIncentive = liquidationIncentiveMantissa *
            borrowTokenPrice;
        uint256 collateralIncentive = seizeTokenPrice * exchangeRate;
        uint256 ratio = (borrowIncentive * 1e18) / collateralIncentive;

        uint256 seizeTokenAmount = IERC20(_seizeToken).balanceOf(_borrower);
        liquidableAmount = (seizeTokenAmount * 1e18) / ratio;
        liquidableAmount = ISFProtocolToken(_borrowToken).convertToUnderlying(
            liquidableAmount
        );

        return liquidableAmount;
    }

    /// @inheritdoc IMarketPositionManager
    function getLiquidableAmount(
        address _borrowToken,
        address _borrower
    ) external view override returns (uint256) {
        (, uint256 borrowAmount, ) = ISFProtocolToken(_borrowToken)
            .getAccountSnapshot(_borrower);
        if (!markets[_borrowToken].isListed) {
            return 0;
        }

        uint256 liquidableAmount;
        if (borrowGuardianPaused[_borrowToken]) {
            liquidableAmount = borrowAmount;
        } else {
            bool validation = _checkValidation(_borrower, _borrowToken, 0, 0);
            liquidableAmount = validation
                ? 0
                : ((borrowAmount * maxLiquidateRate) / FIXED_RATE);
        }

        return liquidableAmount;
    }

    /// @inheritdoc IMarketPositionManager
    function validateLiquidate(
        address _tokenBorrowed,
        address _tokenSeize,
        address _borrower,
        uint256 _liquidateAmount
    ) external view {
        require(
            markets[_tokenBorrowed].isListed && markets[_tokenSeize].isListed,
            "not listed token"
        );

        (, uint256 borrowAmount, ) = ISFProtocolToken(_tokenBorrowed)
            .getAccountSnapshot(_borrower);

        if (borrowGuardianPaused[_tokenBorrowed]) {
            require(
                borrowAmount >= _liquidateAmount,
                "can not liquidate more than borrowed"
            );
        } else {
            // To liquidate, borrower should be under collateralized.
            require(
                !_checkValidation(_borrower, _tokenBorrowed, 0, 0),
                "unable to liquidate"
            );

            uint256 maxLiquidateAmount = (borrowAmount * maxLiquidateRate) /
                FIXED_RATE;
            require(
                maxLiquidateAmount > _liquidateAmount,
                "too much to liquidate"
            );
        }
    }

    /// @inheritdoc IMarketPositionManager
    function validateBorrow(
        address _token,
        address _borrower,
        uint256 _borrowAmount
    ) external override onlyValidCaller(_token) returns (bool) {
        MarketInfo storage info = markets[_token];
        require(!borrowGuardianPaused[_token], "borrow is paused");

        if (!info.accountMembership[_borrower]) {
            // if borrower didn't ever borrow, nothing else
            markets[_token].accountMembership[_borrower] = true;
            if (!accountAssets[_borrower].contains(_token)) {
                accountAssets[_borrower].add(_token);
            }
        }

        require(
            _checkValidation(_borrower, _token, 0, _borrowAmount),
            "under collateralized"
        );

        return true;
    }

    /// @inheritdoc IMarketPositionManager
    function validateRedeem(
        address _token,
        address _redeemer,
        uint256 _redeemAmount
    ) external view override onlyValidCaller(_token) returns (bool) {
        MarketInfo storage info = markets[_token];

        if (!info.accountMembership[_redeemer]) {
            return true;
        }

        require(
            _checkValidation(_redeemer, _token, _redeemAmount, 0),
            "under collateralized"
        );

        return true;
    }

    /// @notice Get borrowable underlying token amount by a user.
    /// @param _account The address of borrower.
    /// @param _token The address of sfToken.
    function getBorrowableAmount(
        address _account,
        address _token
    ) external view override returns (uint256) {
        address[] memory assets = accountAssets[_account].values();
        uint256 length = assets.length;
        if (
            borrowGuardianPaused[_token]
        ) {
            return 0;
        }

        uint256 totalCollateral = 0;
        uint256 totalDebt = 0;
        address account = _account;
        address token = _token;
        uint256 borrowTokenPrice;
        uint256 availableCollateral;

        uint256 accountCollateral;
        uint256 accountDebt;
        for (uint256 i = 0; i < length; i++) {
            uint256 price;
            address asset = assets[i];
            (accountCollateral, accountDebt, price) = _calCollateralAndDebt(
                account,
                asset,
                0,
                0
            );

            if (asset == token) {
                borrowTokenPrice = price;
            }

            totalCollateral += accountCollateral;
            totalDebt += accountDebt;
        }

        if (!accountAssets[account].contains(token)) {
            (
                accountCollateral,
                accountDebt,
                borrowTokenPrice
            ) = _calCollateralAndDebt(account, token, 0, 0);

            totalCollateral += accountCollateral;
            totalDebt += accountDebt;
        }

        availableCollateral = totalDebt >= totalCollateral
            ? 0
            : totalCollateral - totalDebt;

        uint256 borrowableAmount = (availableCollateral * 1e18) /
            borrowTokenPrice;
        uint256 poolAmount = ISFProtocolToken(token).getUnderlyingBalance();
        poolAmount = ISFProtocolToken(token).convertUnderlyingToShare(
            poolAmount
        );
        borrowableAmount = borrowableAmount > poolAmount
            ? poolAmount
            : borrowableAmount;

        return ISFProtocolToken(_token).convertToUnderlying(borrowableAmount);
    }

    function _checkValidation(
        address _account,
        address _token,
        uint256 _redeemAmount,
        uint256 _borrowAmount
    ) internal view returns (bool) {
        address[] memory assets = accountAssets[_account].values();
        uint256 length = assets.length;

        uint256 totalCollateral = 0;
        uint256 totalDebt = 0;
        uint256 redeemAmount = _redeemAmount;
        uint256 borrowAmount = _borrowAmount;
        address account = _account;
        address token = _token;
        for (uint256 i = 0; i < length; i++) {
            address asset = assets[i];
            (
                uint256 accountCollateral,
                uint256 accountDebt,

            ) = _calCollateralAndDebt(
                    account,
                    assets[i],
                    asset == token ? borrowAmount : 0,
                    asset == token ? redeemAmount : 0
                );

            totalCollateral += accountCollateral;
            totalDebt += accountDebt;
        }

        if (!accountAssets[account].contains(token)) {
            (
                uint256 accountCollateral,
                uint256 accountDebt,

            ) = _calCollateralAndDebt(
                    account,
                    token,
                    borrowAmount,
                    redeemAmount
                );

            totalCollateral += accountCollateral;
            totalDebt += accountDebt;
        }

        return totalCollateral > totalDebt;
    }

    function _calCollateralAndDebt(
        address _account,
        address _token,
        uint256 _borrowAmount,
        uint256 _redeemAmount
    )
        internal
        view
        returns (
            uint256 accountCollateral,
            uint256 accountDebt,
            uint256 tokenPrice
        )
    {
        ISFProtocolToken asset = ISFProtocolToken(_token);
        (
            uint256 shareBalance,
            uint256 borrowedAmount,
            uint256 exchangeRate
        ) = asset.getAccountSnapshot(_account);

        tokenPrice = priceOracle.getUnderlyingPrice(address(asset)) * HBARprice / 1e8;
        require(tokenPrice > 0, "price error");

        // accountCollateral is USD amount of user supplied
        accountCollateral = (exchangeRate * shareBalance) / 1e18;
        accountCollateral = (accountCollateral * tokenPrice * borrowCaps[_token]) / 1e20;

        // accountDebt is USD amount of user should pay
        accountDebt = asset.convertUnderlyingToShare(_redeemAmount + _borrowAmount);
        accountDebt =
            (tokenPrice * (accountDebt + borrowedAmount)) / 1e18;
    }

    function updatePrice(uint price)external onlyOwner{
        HBARprice = price;
    }
}
