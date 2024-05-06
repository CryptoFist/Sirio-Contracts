const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
    deploy,
    bigNum,
    deployProxy,
    getCurrentTimestamp,
    smallNum,
    increaseBlock,
    year,
} = require("hardhat-libutils");

const { getDeploymentParam } = require("../scripts/params");

const { erc20_abi } = require("../external_abi/ERC20.abi.json");
const { WETH_abi } = require("../external_abi/WETH.abi.json");
const {
    uniswapV2_router,
} = require("../external_abi/UniswapV2Router.abi.json");

describe("Additional Test for occupied errors", function () {
    let feeRate,
        param,
        underlyingTokenAddress,
        underlyingDecimals,
        name,
        symbol;
    let WBTCWhaleAddress = "0x6daB3bCbFb336b29d06B9C793AEF7eaA57888922";
    let WETHWhaleAddress = "0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3";
    before(async function () {
        [this.deployer, this.tester, this.tester_1] = await ethers.getSigners();

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [WBTCWhaleAddress],
        });
        this.WBTCWhale = await ethers.getSigner(WBTCWhaleAddress);

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [WETHWhaleAddress],
        });
        this.WETHWhale = await ethers.getSigner(WETHWhaleAddress);

        param = getDeploymentParam();
        underlyingTokenAddress = param.WBTCAddress;
        name = "Sirio USD Coin";
        symbol = "sfUSD";
        feeRate = {
            borrowingFeeRate: 100, // 1%
            redeemingFeeRate: 200, // 2%
            claimingFeeRate: 150, // 1.5%
        };

        this.WBTC = new ethers.Contract(
            param.WBTCAddress,
            erc20_abi,
            this.deployer
        );

        this.WETH = new ethers.Contract(
            param.WETHAddress,
            WETH_abi,
            this.deployer
        );

        this.dexRouter = new ethers.Contract(
            param.dexRouterV2Address,
            uniswapV2_router,
            this.deployer
        );

        this.interestRateModel = await deploy(
            "InterestRateModel",
            "InterestRateModel",
            BigInt(param.interestRate.blocksPerYear),
            BigInt(param.interestRate.baseRatePerYear),
            BigInt(param.interestRate.multiplerPerYear),
            BigInt(param.interestRate.jumpMultiplierPerYear),
            BigInt(param.interestRate.kink),
            this.deployer.address,
            param.interestRate.name
        );

        this.priceOracle = await deploy(
            "PriceOracle",
            "PriceOracle",
            param.USDCAddress,
            param.dexRouterV2Address
        );

        this.marketPositionManager = await deployProxy(
            "MarketPositionManager",
            "MarketPositionManager",
            [
                this.priceOracle.address,
                param.maxLiquidateRate,
                BigInt(param.healthcareThresold),
            ]
        );

        this.NftToken = await deploy(
            "NftToken",
            "NftToken",
            this.deployer.address
        );

        this.sfWBTC = await deploy(
            "SFProtocolToken",
            "SFProtocolToken",
            feeRate,
            underlyingTokenAddress,
            this.interestRateModel.address,
            this.marketPositionManager.address,
            this.NftToken.address,
            param.initialExchangeRateMantissa,
            this.dexRouter.address,
            param.WETHAddress,
            name,
            symbol
        );

        this.sfHBAR = await deploy(
            "HBARProtocol",
            "HBARProtocol",
            feeRate,
            param.USDCAddress,
            this.interestRateModel.address,
            this.marketPositionManager.address,
            this.NftToken.address,
            param.initialExchangeRateMantissa,
            this.dexRouter.address,
            "Sirio Wrapped HBAR",
            "sfHBAR"
        );

        await this.marketPositionManager.setBorrowCaps(
            [this.sfWBTC.address, this.sfHBAR.address],
            [78, 60]
        );

        underlyingDecimals = await this.WBTC.decimals();
    });

    it("check deployment", async function () {
        console.log("deployed successfully!");
    });

    it("initialize", async function () {
        await this.marketPositionManager.addToMarket(this.sfWBTC.address);
        await this.marketPositionManager.addToMarket(this.sfHBAR.address);
    });

    describe("Check Borrow", function () {
        describe("Check borrow in SFProtocolToken", function () {
            it("supply underlying", async function () {
                let underlyingAmt = bigNum(100, underlyingDecimals);
                await this.WBTC.connect(this.WBTCWhale).transfer(
                    this.tester.address,
                    BigInt(underlyingAmt)
                );
                await this.WBTC.connect(this.tester).approve(
                    this.sfWBTC.address,
                    BigInt(underlyingAmt)
                );

                await this.sfWBTC
                    .connect(this.tester)
                    .supplyUnderlying(BigInt(underlyingAmt));

                let underlyingBalance =
                    await this.sfWBTC.getUnderlyingBalance();
                let suppliedAmount = await this.sfWBTC.getSuppliedAmount(
                    this.tester.address
                );

                expect(
                    smallNum(underlyingBalance, underlyingDecimals)
                ).to.be.equal(smallNum(suppliedAmount, underlyingDecimals));
            });

            it("borrow underlying", async function () {
                let borrowAmount = bigNum(10, underlyingDecimals);
                await this.sfWBTC
                    .connect(this.tester)
                    .borrow(BigInt(borrowAmount));

                // no collateral to borrow tokens.
                await expect(
                    this.sfWBTC
                        .connect(this.tester_1)
                        .borrow(BigInt(borrowAmount))
                ).to.be.revertedWith("under collateralized");
            });

            it("supply with tester_1 and borrow", async function () {
                let underlyingAmt = bigNum(50, underlyingDecimals);
                await this.WBTC.connect(this.WBTCWhale).transfer(
                    this.tester_1.address,
                    BigInt(underlyingAmt)
                );
                await this.WBTC.connect(this.tester_1).approve(
                    this.sfWBTC.address,
                    BigInt(underlyingAmt)
                );

                await this.sfWBTC
                    .connect(this.tester_1)
                    .supplyUnderlying(BigInt(underlyingAmt));

                let borrowAmount = bigNum(20, underlyingDecimals);
                console.log("borrow with tester_1");
                await this.sfWBTC
                    .connect(this.tester_1)
                    .borrow(BigInt(borrowAmount));

                console.log("borrow with tester");
                await this.sfWBTC
                    .connect(this.tester)
                    .borrow(BigInt(borrowAmount));
            });
        });

        describe("Check borrow in HBARProtocol", function () {
            it("supply underlying", async function () {
                let underlyingAmt = bigNum(20, underlyingDecimals);
                await this.WETH.connect(this.WETHWhale).transfer(
                    this.tester.address,
                    BigInt(underlyingAmt)
                );
                await this.WETH.connect(this.tester).withdraw(
                    BigInt(underlyingAmt)
                );
                await this.sfHBAR
                    .connect(this.tester)
                    .supplyUnderlying(BigInt(underlyingAmt), {
                        value: BigInt(underlyingAmt),
                    });

                let underlyingBalance =
                    await this.sfHBAR.getUnderlyingBalance();
                let suppliedAmount = await this.sfHBAR.getSuppliedAmount(
                    this.tester.address
                );

                console.log(
                    smallNum(underlyingBalance, 8),
                    smallNum(suppliedAmount, 8)
                );
            });

            it("borrow underlying", async function () {
                let borrowAmount = bigNum(10, underlyingDecimals);
                await this.sfHBAR
                    .connect(this.tester)
                    .borrow(BigInt(borrowAmount));

                await this.sfHBAR
                    .connect(this.tester_1)
                    .borrow(BigInt(borrowAmount));
            });
        });
    });

    describe("Check liquidation", function () {
        describe("Check liquidation in SFProtocolToken", function () {
            it("liquidateBorrow with SFProtocolToken", async function () {
                let [shareBalance, borrowedAmount, exchangeRate] =
                    await this.sfWBTC.getAccountSnapshot(this.tester.address);
                console.log(shareBalance, borrowedAmount, exchangeRate);
                console.log("shareBalance: ", smallNum(shareBalance, 18));
                console.log("borrowedAmount: ", smallNum(borrowedAmount, 18));
            });
        });

        describe("Check liquidation in HBARProtocol", function () {});
    });
});
