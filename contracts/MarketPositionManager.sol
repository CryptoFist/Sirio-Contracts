// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IMarketPositionManager.sol";
import "./interfaces/ISFProtocolToken.sol";
import "./interfaces/IPriceOracle.sol";




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

    /// @notice Borrowers addresses
    address[] public borrowerList;

    /// @notice Multiplier representing the discount on collateral that a liquidator receives
    uint256 public liquidationIncentiveMantissa;

    /// @notice The max liquidate rate based on borrowed amount.
    uint16 public maxLiquidateRate;

    /// @notice 10,000 = 100%
    uint16 public constant FIXED_RATE = 10_000;

    /// @notice HBAR price on the market
    uint256 public HBARprice;

    uint256 public HealthcareThreshold;

    IPriceOracle public priceOracle;

    modifier onlyValidCaller(address _token) {
        require(msg.sender == _token, "invalid caller");
        require(markets[_token].isListed, "not listed token");
        _;
    }

    function initialize(
        address _priceOracle,
        uint16 _maxLiquidateRate,
        uint256 _healthcareThreshold
    ) public initializer {
        __Ownable_init();
        setPriceOracle(_priceOracle);
        setMaxLiquidateRate(_maxLiquidateRate);
        liquidationIncentiveMantissa = 1e17;
        HBARprice = 8*10**16;
        HealthcareThreshold = _healthcareThreshold;
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

    function checkHealthcare(
        address _borrower
    ) public view returns(uint256, uint256, uint256){
        address[] memory assets = accountAssets[_borrower].values();
        uint256 length = assets.length;

        uint256 totalCollateral = 0;
        uint256 totalDebt = 0;
        uint256 totalSupplied = 0;
        address account = _borrower;
        for (uint256 i = 0; i < length; i++) {
            (
                uint256 accountCollateral,
                uint256 accountDebt,
            ) = _calCollateralAndDebt(
                    account,
                    assets[i],
                    0,
                    0
                );

            totalCollateral += accountCollateral;
            totalDebt += accountDebt;
            totalSupplied += accountCollateral* 10**2 / borrowCaps[assets[i]];
        }
        uint256 healthcare = totalDebt * 1e18 / totalCollateral;
        return (
            healthcare, 
            totalDebt,
            totalSupplied
        );                           
    }

    function checkLiquidation() public view returns(
        address[] memory borrowers, 
        uint256[] memory debts, 
        uint256[] memory reward)
    {
        borrowers = new address[](borrowerList.length);
        debts = new uint256[](borrowerList.length);
        reward = new uint256[](borrowerList.length);
        uint j = 0;
        for (uint256 i = 0; i < borrowerList.length; i++) {
            ( uint256 healthcare, uint256 debt, uint256 supplied) = checkHealthcare(borrowerList[i]);
            if (healthcare >= HealthcareThreshold){
                borrowers[j] = borrowerList[i];
                debts[j] = debt;
                uint256 amount = supplied * liquidationIncentiveMantissa / 1e18;
                reward[j] = supplied >= (debt + amount) ? (debt + amount/2) : (debt + (supplied - debt)/2);
                j++;
            }
        }
    }

    function calcLiquidationDetail(
        address borrower, 
        uint256 liquidateAmount
        ) public view returns(
            address[] memory suppliedAssets, 
            uint256[] memory liquidateAmounts,
            address[] memory borrowedAssets,
            uint256[] memory borrowedAmounts)
    {
        address[] memory assets = accountAssets[borrower].values();
        suppliedAssets = new address[](assets.length);
        borrowedAssets = new address[](assets.length);
        liquidateAmounts = new uint256[](assets.length);
        borrowedAmounts = new uint256[](assets.length);
        uint supplyCount = 0; 
        uint borrowCount = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            ISFProtocolToken asset = ISFProtocolToken(assets[i]);
            (
                uint256 shareBalance,
                uint256 borrowedAmount,
                uint256 exchangeRate
            ) = asset.getAccountSnapshot(borrower);
            if(shareBalance > 0 && liquidateAmount > 0){
                suppliedAssets[supplyCount] = assets[i];
                uint256 suppliedAmount = (exchangeRate * shareBalance) / 1e18;
                uint256 tokenPrice = priceOracle.getUnderlyingPrice(assets[i]) * HBARprice / 1e18;
                if(liquidateAmount >= (suppliedAmount * tokenPrice / 1e18)){
                    liquidateAmounts[supplyCount] = suppliedAmount;
                    liquidateAmount -= suppliedAmount * tokenPrice / 1e18;
                }
                else{
                    liquidateAmounts[supplyCount] = liquidateAmount * 1e18 /tokenPrice;
                    liquidateAmount = 0;
                }

                supplyCount++;
            }
            if(borrowedAmount > 0){
                borrowedAssets[borrowCount] = assets[i];
                borrowedAmounts[borrowCount] = borrowedAmount;
                borrowCount++;
            }
        }
    }

    function liquidateBorrow(address _borrower, address _token, uint256 _amount) external {
        require(_amount > 0, "invalid liquidation amount");
        address _liquidator = msg.sender;
        require(validateLiquidate(_liquidator, _borrower, _amount), "invalid liquidation");
        require(_liquidator != _borrower, "invalid liquidator");
        (
            address[] memory suppliedAssets, 
            uint256[] memory liquidateAmounts,
            address[] memory borrowedAssets,
            uint256[] memory borrowedAmounts
        ) = calcLiquidationDetail(_borrower, _amount);
        ISFProtocolToken asset = ISFProtocolToken(_token);
        ( , uint256 debt ,) = checkHealthcare(_borrower);
        uint256 liquidateProtocolFee = _amount - debt;
        for (uint256 i = 0; i < borrowedAssets.length; i++){
            if(borrowedAmounts[i] > 0 && borrowedAssets[i] != address(0)){
                asset.liquidateBorrow(_liquidator, _borrower, borrowedAssets[i], borrowedAmounts[i]);
                if(borrowedAssets[i] != _token){
                    ISFProtocolToken(borrowedAssets[i]).removeBorrow(_borrower, borrowedAmounts[i]);
                }
            }
        }
        for (uint j = 0; j < suppliedAssets.length; j++){
            if(liquidateAmounts[j] > 0 && suppliedAssets[j] != address(0)){
                ISFProtocolToken(suppliedAssets[j]).seize(_liquidator, _borrower, liquidateAmounts[j]);
            }
        }
        (
            address[] memory Assets, 
            uint256[] memory Amounts, ,
        ) = calcLiquidationDetail(_borrower, liquidateProtocolFee);
        for(uint k = 0; k < Assets.length; k++){
            if(Amounts[k] > 0){
                ISFProtocolToken(suppliedAssets[k]).seizeToprotocol(_borrower, Amounts[k]);
            }
        }
    }

    /// @inheritdoc IMarketPositionManager
    function validateLiquidate(
        address _liquidator,
        address _borrower,
        uint256 _liquidateAmount
    ) public view returns(bool) {
        require(
            validateBorrower(_borrower),
            "not listed borrower"
        );

        ( uint256 healthcare, uint256 debt, ) = checkHealthcare(_borrower);
        (uint256 liquidatorHealthcare, uint256 liquidatordebt, uint256 supplied) = checkHealthcare(_liquidator);

        require( healthcare >= HealthcareThreshold, "not subject of liquidation");
        require( liquidatorHealthcare < HealthcareThreshold, "can't liquidate");
        require((supplied - liquidatordebt) > debt, "liquidator doesn't have enough assets");

        return _liquidateAmount > debt;
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

        if (!validateBorrower(_borrower)) {
            borrowerList.push(_borrower);
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

        availableCollateral = totalDebt >= ( totalCollateral * 95 / 100)
            ? 0
            : ( totalCollateral * 95 / 100)  - totalDebt;

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

    /// @notice Get redeemable underlying token amount by a user.
    /// @param _account The address of supplier.
    /// @param _token The address of sfToken.
    function getRedeemableAmount(
        address _account,
        address _token
    ) external view override returns (uint256) {
        address[] memory assets = accountAssets[_account].values();
        uint256 length = assets.length;
        uint256 totalCollateral = 0;
        uint256 totalDebt = 0;
        uint256 totalSupplied = 0;
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
            totalSupplied += accountCollateral* 10**2 / borrowCaps[asset];
        }

        if (!accountAssets[account].contains(token)) {
            (
                accountCollateral,
                accountDebt,
                borrowTokenPrice
            ) = _calCollateralAndDebt(account, token, 0, 0);

            totalCollateral += accountCollateral;
            totalDebt += accountDebt;
            totalSupplied += accountCollateral* 10**2 / borrowCaps[token];
        }

        availableCollateral = totalDebt >= ( totalCollateral * 95 / 100)
            ? 0
            : ( totalCollateral * 95 / 100) - totalDebt;
        if(totalDebt == 0) {
            availableCollateral = totalSupplied;
        }

        uint256 redeemableAmount = (availableCollateral * 1e18) /
            borrowTokenPrice;
        redeemableAmount = ISFProtocolToken(_token).convertToUnderlying(redeemableAmount);
        uint256 poolAmount = ISFProtocolToken(token).getUnderlyingBalance();
        uint256 supplied = ISFProtocolToken(_token).getSuppliedAmount(account);
        redeemableAmount = redeemableAmount > supplied
            ? supplied
            : redeemableAmount;
        redeemableAmount = redeemableAmount > poolAmount
            ? poolAmount
            : redeemableAmount;

        return redeemableAmount;
    }

    function validateBorrower(address _borrower) internal view returns (bool) {
        for (uint256 i = 0; i < borrowerList.length; i++) {
            if (borrowerList[i] == _borrower) {
                return true; // _borrower is in the borrowerList
            }
        }
        return false; // _borrower is not in the borrowerList
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

        return (totalCollateral * 95 /100) >= totalDebt;
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

        tokenPrice = priceOracle.getUnderlyingPrice(address(asset)) * HBARprice / 1e18;
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

    function updateHealthcareT(uint thresold) external onlyOwner{
        HealthcareThreshold = thresold;
    }
}
