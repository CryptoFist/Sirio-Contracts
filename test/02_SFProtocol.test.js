const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
    deploy,
    bigNum,
    deployProxy,
    getCurrentTimestamp,
    smallNum,
} = require("hardhat-libutils");

const { getDeploymentParam } = require("../scripts/params");

const { erc20_abi } = require("../external_abi/ERC20.abi.json");
const {
    uniswapV2_router,
} = require("../external_abi/UniswapV2Router.abi.json");

describe("Sirio Finance Protocol test", function () {
    let feeRate, param, underlyingTokenAddress, name, symbol;
    let DAIAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
    before(async function () {
        [
            this.deployer,
            this.supplier_1,
            this.supplier_2,
            this.borrower_1,
            this.borrower_2,
        ] = await ethers.getSigners();

        param = getDeploymentParam();
        underlyingTokenAddress = param.USDCAddress;
        name = "Sirio USD Coin";
        symbol = "sfUSD";
        feeRate = {
            borrowingFeeRate: 100, // 1%
            redeemingFeeRate: 200, // 2%
        };

        this.USDC = new ethers.Contract(
            param.USDCAddress,
            erc20_abi,
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
            DAIAddress,
            param.dexRouterV2Address
        );

        this.marketPositionManager = await deployProxy(
            "MarketPositionManager",
            "MarketPositionManager",
            [this.priceOracle.address, param.maxLiquidateRate]
        );

        this.sfUSDC = await deployProxy("SFProtocolToken", "SFProtocolToken", [
            feeRate,
            underlyingTokenAddress,
            this.interestRateModel.address,
            this.marketPositionManager.address,
            param.initialExchangeRateMantissa,
            name,
            symbol,
        ]);
    });

    it("check deployment", async function () {
        console.log("deployed successfully!");
    });

    describe("supply underlying tokens", function () {
        let supplyAmount;
        it("buy some USDC for supply", async function () {
            await this.dexRouter
                .connect(this.supplier_1)
                .swapExactETHForTokens(
                    0,
                    [param.WETHAddress, this.USDC.address],
                    this.supplier_1.address,
                    BigInt(await getCurrentTimestamp()) + BigInt(100),
                    { value: bigNum(5, 18) }
                );

            supplyAmount = await this.USDC.balanceOf(this.supplier_1.address);
            console.log("swappedAmount: ", smallNum(supplyAmount, 6));
            supplyAmount = BigInt(supplyAmount) / BigInt(4);

            await this.USDC.connect(this.supplier_1).approve(
                this.sfUSDC.address,
                BigInt(supplyAmount)
            );
        });

        it("reverts if supply amount is invalid", async function () {
            await expect(
                this.sfUSDC.connect(this.supplier_1).supplyUnderlying(0)
            ).to.be.revertedWith("invalid supply amount");
        });

        it("reverts if token is not listed", async function () {
            await expect(
                this.sfUSDC
                    .connect(this.supplier_1)
                    .supplyUnderlying(BigInt(supplyAmount))
            ).to.be.revertedWith("not listed token");
        });

        it("add USDC to markets", async function () {
            // reverts if caller is not the owner
            await expect(
                this.marketPositionManager
                    .connect(this.supplier_1)
                    .addToMarket(this.sfUSDC.address)
            ).to.be.revertedWith("Ownable: caller is not the owner");

            // add sfUSDC to markets
            await this.marketPositionManager.addToMarket(this.sfUSDC.address);

            // reverts if token is already added
            await expect(
                this.marketPositionManager.addToMarket(this.sfUSDC.address)
            ).to.be.revertedWith("already added");
        });

        it("supply and check", async function () {
            let beforeBal = await this.sfUSDC.balanceOf(
                this.supplier_1.address
            );
            await this.sfUSDC
                .connect(this.supplier_1)
                .supplyUnderlying(BigInt(supplyAmount));
            let afterBal = await this.sfUSDC.balanceOf(this.supplier_1.address);
            let receivedShareAmounts = smallNum(
                BigInt(afterBal) - BigInt(beforeBal),
                18
            );
            let originSupplyAmount = smallNum(supplyAmount, 6);
            console.log("received shares: ", receivedShareAmounts);

            // this supply is the first time and initialExchageRate is 0.02,
            // so shareAmount should be supplyAmount * 50
            expect(receivedShareAmounts / originSupplyAmount).to.be.closeTo(
                50,
                0.00001
            );
        });

        it("supply again and check", async function () {
            let originShare = await this.sfUSDC.balanceOf(
                this.supplier_1.address
            );
            await this.USDC.connect(this.supplier_1).approve(
                this.sfUSDC.address,
                BigInt(supplyAmount)
            );
            let beforeBal = await this.sfUSDC.balanceOf(
                this.supplier_1.address
            );
            await this.sfUSDC
                .connect(this.supplier_1)
                .supplyUnderlying(BigInt(supplyAmount));
            let afterBal = await this.sfUSDC.balanceOf(this.supplier_1.address);
            let receivedShareAmounts = BigInt(afterBal) - BigInt(beforeBal);
            expect(smallNum(originShare, 18)).to.be.equal(
                smallNum(receivedShareAmounts, 18)
            );
        });
    });

    describe("redeem & redeemExactUnderlying", function () {
        describe("redeem", function () {
            it("reverts if share amount is invalid", async function () {
                await expect(
                    this.sfUSDC.connect(this.supplier_1).redeem(0)
                ).to.be.revertedWith("invalid amount");
            });

            it("redeem and check", async function () {
                let suppliedAmount = await this.sfUSDC.getSuppliedAmount(
                    this.supplier_1.address
                );
                let ownedShareAmount = await this.sfUSDC.balanceOf(
                    this.supplier_1.address
                );

                let redeemShare = BigInt(ownedShareAmount) / BigInt(2);
                let expectUnderlyingAmount = BigInt(suppliedAmount) / BigInt(2);
                let redeemFee = feeRate.redeemingFeeRate;
                let feeAmount =
                    (BigInt(expectUnderlyingAmount) * BigInt(redeemFee)) /
                    BigInt(10000);
                expectUnderlyingAmount =
                    BigInt(expectUnderlyingAmount) - BigInt(feeAmount);

                let beforeOwnerBal = await this.USDC.balanceOf(
                    this.deployer.address
                );
                let beforeRecvBal = await this.USDC.balanceOf(
                    this.supplier_1.address
                );
                await this.sfUSDC
                    .connect(this.supplier_1)
                    .redeem(BigInt(redeemShare));
                let afterOwnerBal = await this.USDC.balanceOf(
                    this.deployer.address
                );
                let afterRecvBal = await this.USDC.balanceOf(
                    this.supplier_1.address
                );

                let ownerReceivedAmount =
                    BigInt(afterOwnerBal) - BigInt(beforeOwnerBal);
                let redeemerReceivedAmount =
                    BigInt(afterRecvBal) - BigInt(beforeRecvBal);

                expect(smallNum(ownerReceivedAmount, 6)).to.be.closeTo(
                    smallNum(feeAmount, 6),
                    0.0001
                );
                expect(smallNum(redeemerReceivedAmount, 6)).to.be.closeTo(
                    smallNum(expectUnderlyingAmount, 6),
                    0.0001
                );
            });
        });

        describe("redeemExactUnderlying", function () {
            it("reverts if amount is invalid", async function () {
                await expect(
                    this.sfUSDC
                        .connect(this.supplier_1)
                        .redeemExactUnderlying(0)
                ).to.be.revertedWith("invalid amount");
            });

            it("redeem and check", async function () {
                let suppliedAmount = await this.sfUSDC.getSuppliedAmount(
                    this.supplier_1.address
                );
                let redeemAmount = BigInt(suppliedAmount) / BigInt(2);
                let ownedShareAmount = await this.sfUSDC.balanceOf(
                    this.supplier_1.address
                );
                let feeAmount =
                    (BigInt(redeemAmount) * BigInt(feeRate.redeemingFeeRate)) /
                    BigInt(10000);
                let expectRedeemAmount =
                    BigInt(redeemAmount) - BigInt(feeAmount);

                let beforeUnderlyingBal = await this.USDC.balanceOf(
                    this.supplier_1.address
                );
                let beforeShareBal = await this.sfUSDC.balanceOf(
                    this.supplier_1.address
                );
                await this.sfUSDC
                    .connect(this.supplier_1)
                    .redeemExactUnderlying(BigInt(redeemAmount));
                let afterUnderlyingBal = await this.USDC.balanceOf(
                    this.supplier_1.address
                );
                let afterShareBal = await this.sfUSDC.balanceOf(
                    this.supplier_1.address
                );

                expect(
                    BigInt(afterUnderlyingBal) - BigInt(beforeUnderlyingBal)
                ).to.be.equal(BigInt(expectRedeemAmount));
                expect(
                    BigInt(beforeShareBal) - BigInt(afterShareBal)
                ).to.be.equal(BigInt(ownedShareAmount) / BigInt(2));
            });
        });
    });
});
