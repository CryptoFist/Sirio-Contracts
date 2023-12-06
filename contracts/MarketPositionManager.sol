// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/ISFProtocolToken.sol";
import "./interfaces/IMarketPositionManager.sol";

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

    IPriceOracle public priceOracle;

    modifier onlyValidCaller(address _token) {
        require(msg.sender == _token, "invalid caller");
        require(markets[_token].isListed, "not listed token");
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    /// @notice Returns whether the given account is entered in the given asset
    /// @param _account The address of the account to check
    /// @param _token The cToken to check
    /// @return True if the account is in the asset, otherwise false.
    function checkMembership(
        address _account,
        address _token
    ) external view returns (bool) {
        return markets[_token].accountMembership[_account];
    }

    /// @inheritdoc IMarketPositionManager
    function validateSupply(
        address _token
    ) external view override onlyValidCaller(_token) {
        require(!supplyGuardianPaused[_token], "supplying is paused");
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
            info.accountMembership[_borrower] = true;
            accountAssets[_borrower].add(_token);
            return true;
        }

        uint256 borrowCap = borrowCaps[_token];
        if (borrowCap > 0) {
            uint256 totalBorrows = ISFProtocolToken(_token).totalBorrows();
            require(
                totalBorrows + _borrowAmount <= borrowCap,
                "market borrow cap reached"
            );
        }

        _checkValidation(_borrower, _token, 0, _borrowAmount);

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

        _checkValidation(_redeemer, _token, _redeemAmount, 0);

        return true;
    }

    function _checkValidation(
        address _account,
        address _token,
        uint256 _redeemAmount,
        uint256 _borrowAmount
    ) internal view {
        address[] memory assets = accountAssets[_account].values();
        uint256 length = assets.length;
        if (length == 0) {
            return;
        }

        uint256 totalCollateral = 0;
        uint256 totalDebt = 0;
        for (uint256 i = 0; i < length; i++) {
            ISFProtocolToken asset = ISFProtocolToken(assets[i]);
            (
                uint256 shareBalance,
                uint256 borrowedAmount,
                uint256 exchangeRate
            ) = asset.getAccountSnapshot(_account);

            uint256 tokenPrice = priceOracle.getUnderlyingPrice(address(asset));
            require(tokenPrice > 0, "price error");

            // accountCollateral is USD amount of user supplied
            uint256 accountCollateral = (exchangeRate * shareBalance) / 1e18;
            accountCollateral = (accountCollateral * tokenPrice) / 1e18;
            totalCollateral += accountCollateral;

            // accountDebt is USD amount of user should pay
            uint256 accountDebt = (tokenPrice * borrowedAmount) / 1e18;
            if (address(asset) == _token) {
                accountDebt +=
                    (tokenPrice * (_redeemAmount + _borrowAmount)) /
                    1e18;
            }
            totalDebt += accountDebt;
        }

        require(totalCollateral > totalDebt, "under collateralized");
    }
}
