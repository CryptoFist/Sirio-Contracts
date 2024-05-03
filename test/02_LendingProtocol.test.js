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

describe("Sirio Finance Protocol test", function () {
    let feeRate, param, underlyingTokenAddress, name, symbol;
    let WBTCWhaleAddress = "0x6daB3bCbFb336b29d06B9C793AEF7eaA57888922";
    before(async function () {
        [this.deployer, this.tester, this.tester_1] = await ethers.getSigners();

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [WBTCWhaleAddress],
        });
        this.WBTCWhale = await ethers.getSigner(WBTCWhaleAddress);

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
            param.USDCAddress,
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
    });

    it("check deployment", async function () {
        console.log("deployed successfully!");
    });

    describe("pause and check functions", function () {
        describe("pause", function () {
            it("reverts if caller is not the owner", async function () {
                await expect(this.sfWBTC.connect(this.tester).pause()).to.be
                    .reverted;
            });

            it("pause", async function () {
                await this.sfWBTC.pause();
            });

            it("reverts if already paused", async function () {
                await expect(this.sfWBTC.pause()).to.be.reverted;
            });
        });

        describe("check functions that it reverts", function () {
            it("supplyUnderlying", async function () {
                await expect(this.sfWBTC.supplyUnderlying(100)).to.be.reverted;
            });

            it("redeem", async function () {
                await expect(this.sfWBTC.redeem(100)).to.be.reverted;

                await expect(this.sfWBTC.redeemExactUnderlying(1000)).to.be
                    .reverted;
            });

            it("borrow", async function () {
                await expect(this.sfWBTC.borrow(1000)).to.be.reverted;
            });
        });
    });

    describe("unpause", function () {
        it("reverts if caller is not the owner", async function () {
            await expect(this.sfWBTC.connect(this.tester).unpause()).to.be
                .reverted;
        });

        it("unpause", async function () {
            await this.sfWBTC.unpause();
        });

        it("reverts if already unpaused", async function () {
            await expect(this.sfWBTC.unpause()).to.be.reverted;
        });
    });

    describe("supply underlying tokens", function () {
        let supplyAmount = 100000000;

        it("reverts if supply amount is invalid", async function () {
            await expect(this.sfWBTC.supplyUnderlying(0)).to.be.reverted;
        });

        it("reverts if token is not listed", async function () {
            await expect(this.sfWBTC.supplyUnderlying(supplyAmount)).to.be
                .reverted;
        });

        it("add WBTC and HBAR to markets", async function () {
            // add sfWBTC to markets
            await this.marketPositionManager.addToMarket(this.sfWBTC.address);
            await this.marketPositionManager.addToMarket(this.sfHBAR.address);

            // reverts if token is already added
            await expect(
                this.marketPositionManager.addToMarket(this.sfWBTC.address)
            ).to.be.reverted;
        });

        it("reverts if token is not approved", async function () {
            await expect(this.sfWBTC.supplyUnderlying(BigInt(supplyAmount))).to
                .be.reverted;
            await this.WBTC.approve(this.sfWBTC.address, BigInt(supplyAmount));
        });

        it("reverts if token is not associated", async function () {
            await expect(this.sfWBTC.supplyUnderlying(BigInt(supplyAmount))).to
                .be.reverted;
            await this.sfWBTC.tokenAssociate(param.WBTCAddress);
        });

        it("supply and check", async function () {
            let wbtcAmount = await this.WBTC.balanceOf(this.WBTCWhale.address);
            console.log(smallNum(wbtcAmount, 8));
            await this.WBTC.connect(this.WBTCWhale).transfer(
                this.deployer.address,
                BigInt(wbtcAmount)
            );

            let beforeBal = await this.sfWBTC.balanceOf(this.deployer.address);
            await this.sfWBTC
                .connect(this.deployer)
                .supplyUnderlying(BigInt(supplyAmount));
            let afterBal = await this.sfWBTC.balanceOf(this.deployer.address);
            let receivedShareAmounts = smallNum(
                BigInt(afterBal) - BigInt(beforeBal),
                18
            );
            let originSupplyAmount = smallNum(supplyAmount, 8);
            console.log("received shares: ", receivedShareAmounts);

            // this supply is the first time and initialExchageRate is 0.02,
            // so shareAmount should be supplyAmount * 50
            expect(receivedShareAmounts / originSupplyAmount).to.be.closeTo(
                50,
                0.00001
            );
        });

        it("supply again and check", async function () {
            await this.WBTC.transfer(this.tester.address, BigInt(supplyAmount));
            await this.WBTC.connect(this.tester).approve(
                this.sfWBTC.address,
                BigInt(supplyAmount)
            );
            let beforeBal = await this.sfWBTC.balanceOf(this.tester.address);
            await this.sfWBTC
                .connect(this.tester)
                .supplyUnderlying(BigInt(supplyAmount));
            let afterBal = await this.sfWBTC.balanceOf(this.tester.address);
            let originSupplyAmount = smallNum(supplyAmount, 8);
            let receivedShareAmounts = smallNum(
                BigInt(afterBal) - BigInt(beforeBal),
                18
            );
            expect(receivedShareAmounts / originSupplyAmount).to.be.closeTo(
                50,
                0.00001
            );
        });
    });

    describe("redeem & redeemExactUnderlying", function () {
        describe("redeem", function () {
            it("reverts if share amount is invalid", async function () {
                await expect(this.sfWBTC.connect(this.deployer).redeem(0)).to.be
                    .reverted;
            });

            it("redeem and check", async function () {
                let suppliedAmount = await this.sfWBTC.getSuppliedAmount(
                    this.tester.address
                );
                let ownedShareAmount = await this.sfWBTC.balanceOf(
                    this.tester.address
                );

                let redeemShare = BigInt(ownedShareAmount) / BigInt(2);
                let expectUnderlyingAmount = BigInt(suppliedAmount) / BigInt(2);
                let redeemFee = feeRate.redeemingFeeRate;
                let feeAmount =
                    (BigInt(expectUnderlyingAmount) * BigInt(redeemFee)) /
                    BigInt(10000);
                expectUnderlyingAmount =
                    BigInt(expectUnderlyingAmount) - BigInt(feeAmount);

                let beforeOwnerBal = await this.WBTC.balanceOf(
                    this.deployer.address
                );
                let beforeRecvBal = await this.WBTC.balanceOf(
                    this.tester.address
                );
                await this.sfWBTC
                    .connect(this.tester)
                    .redeem(BigInt(redeemShare));
                let afterOwnerBal = await this.WBTC.balanceOf(
                    this.deployer.address
                );
                let afterRecvBal = await this.WBTC.balanceOf(
                    this.tester.address
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
                    this.sfWBTC.connect(this.tester).redeemExactUnderlying(0)
                ).to.be.reverted;
            });

            it("redeem and check", async function () {
                let suppliedAmount = await this.sfWBTC.getSuppliedAmount(
                    this.tester.address
                );
                let redeemAmount = BigInt(suppliedAmount) / BigInt(2);
                let ownedShareAmount = await this.sfWBTC.balanceOf(
                    this.tester.address
                );
                let feeAmount =
                    (BigInt(redeemAmount) * BigInt(feeRate.redeemingFeeRate)) /
                    BigInt(10000);
                let expectRedeemAmount =
                    BigInt(redeemAmount) - BigInt(feeAmount);

                let beforeUnderlyingBal = await this.WBTC.balanceOf(
                    this.tester.address
                );
                let beforeShareBal = await this.sfWBTC.balanceOf(
                    this.tester.address
                );
                await this.sfWBTC
                    .connect(this.tester)
                    .redeemExactUnderlying(BigInt(redeemAmount));
                let afterUnderlyingBal = await this.WBTC.balanceOf(
                    this.tester.address
                );
                let afterShareBal = await this.sfWBTC.balanceOf(
                    this.tester.address
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

    describe("borrow", function () {
        let poolBalance, borrowAmount;
        it("get current supplied amount", async function () {
            poolBalance = await this.sfWBTC.getUnderlyingBalance();
            console.log("current PoolBalance: ", smallNum(poolBalance, 6));
            borrowAmount = BigInt(poolBalance) / BigInt(5);
        });

        it("reverts if borrower has not enough collateral", async function () {
            let borrowableAmount =
                await this.marketPositionManager.getBorrowableAmount(
                    this.tester_1.address,
                    this.sfWBTC.address
                );
            expect(borrowableAmount).to.be.equal(0);
            await expect(
                this.sfWBTC.connect(this.tester_1).borrow(BigInt(borrowAmount))
            ).to.be.reverted;
        });

        it("borrow & collateral check", async function () {
            let borrowableAmount =
                await this.marketPositionManager.getBorrowableAmount(
                    this.deployer.address,
                    this.sfWBTC.address
                );
            expect(smallNum(borrowableAmount, 8)).to.be.greaterThanOrEqual(
                smallNum(borrowAmount, 8)
            );
            let beforeBal = await this.WBTC.balanceOf(this.deployer.address);
            await this.sfWBTC
                .connect(this.deployer)
                .borrow(BigInt(borrowAmount));
            let afterBal = await this.WBTC.balanceOf(this.deployer.address);
            expect(afterBal - beforeBal).to.be.equal(borrowAmount);
        });

        it("reverts if not enough supply pool even though borrower has enough collateral", async function () {
            let WBTCBorrowableAmount =
                await this.marketPositionManager.getBorrowableAmount(
                    this.deployer.address,
                    this.sfWBTC.address
                );
            expect(smallNum(WBTCBorrowableAmount, 6)).to.be.greaterThan(0);

            expect(
                smallNum(
                    await this.marketPositionManager.getBorrowableAmount(
                        this.deployer.address,
                        this.sfHBAR.address
                    ),
                    18
                )
            ).to.be.equal(0);

            await expect(
                this.sfHBAR
                    .connect(this.deployer)
                    .borrow(BigInt(WBTCBorrowableAmount))
            ).to.be.reverted;
        });

        it("supply HBAR with tester", async function () {
            let supplyAmount = bigNum(5, 18);

            await this.sfHBAR
                .connect(this.tester)
                .supplyUnderlying(BigInt(supplyAmount / 10 ** 10), {
                    value: BigInt(supplyAmount),
                });
        });

        it("borrow WBTC", async function () {
            let borrowableWBTCAmount =
                await this.marketPositionManager.getBorrowableAmount(
                    this.tester.address,
                    this.sfWBTC.address
                );

            let beforeWBTCBal = await this.WBTC.balanceOf(this.tester.address);
            let [, beforeBorrowedAmount] = await this.sfWBTC.getAccountSnapshot(
                this.tester.address
            );
            let beforeTotalBorrows = await this.sfWBTC.totalBorrows();
            let beforeTotalReserves = await this.sfWBTC.totalReserves();
            let beforeBorrowIndex = await this.sfWBTC.borrowIndex();
            let beforeSupplyRate = await this.sfWBTC.supplyRatePerBlock();
            expect(
                await this.marketPositionManager.checkMembership(
                    this.tester.address,
                    this.sfWBTC.address
                )
            ).to.be.equal(false);
            await this.sfWBTC
                .connect(this.tester)
                .borrow(BigInt(borrowableWBTCAmount));
            expect(
                await this.marketPositionManager.checkMembership(
                    this.tester.address,
                    this.sfWBTC.address
                )
            ).to.be.equal(true);

            let afterSupplyRate = await this.sfWBTC.supplyRatePerBlock();
            let afterWBTCBal = await this.WBTC.balanceOf(this.tester.address);
            let [, afterBorrowedAmount] = await this.sfWBTC.getAccountSnapshot(
                this.tester.address
            );
            let afterTotalBorrows = await this.sfWBTC.totalBorrows();
            let afterTotalReserves = await this.sfWBTC.totalReserves();
            let afterBorrowIndex = await this.sfWBTC.borrowIndex();

            let receviedWBTC = BigInt(afterWBTCBal) - BigInt(beforeWBTCBal);
            let borrowedAmount =
                BigInt(afterBorrowedAmount) - BigInt(beforeBorrowedAmount);
            let totalBorrows =
                BigInt(afterTotalBorrows) - BigInt(beforeTotalBorrows);
            let totalReserves =
                BigInt(afterTotalReserves) - BigInt(beforeTotalReserves);

            let feeAmount =
                (BigInt(bigNum(borrowableWBTCAmount, 10)) *
                    BigInt(feeRate.borrowingFeeRate)) /
                BigInt(10000);
            let expectAmount = BigInt(borrowedAmount) - BigInt(feeAmount);

            expect(smallNum(afterBorrowIndex, 18)).to.be.greaterThan(
                smallNum(beforeBorrowIndex, 18)
            );

            expect(smallNum(receviedWBTC, 8)).to.be.closeTo(
                smallNum(expectAmount, 18),
                0.0001
            );
            expect(smallNum(totalBorrows, 18)).to.be.closeTo(
                smallNum(borrowableWBTCAmount, 8),
                0.0001
            );
            expect(BigInt(totalReserves)).to.be.equal(BigInt(0));
            expect(smallNum(borrowedAmount, 18)).to.be.equal(
                smallNum(borrowableWBTCAmount, 8)
            );

            expect(
                await this.marketPositionManager.getBorrowableAmount(
                    this.tester.address,
                    this.sfWBTC.address
                )
            ).to.be.equal(0);

            expect(Number(afterSupplyRate)).to.be.greaterThan(
                Number(beforeSupplyRate)
            );
        });

        it("increase blockNumber and check borrowAmount", async function () {
            let [, beforeBorrowedAmount] = await this.sfWBTC.getAccountSnapshot(
                this.tester.address
            );

            let beforeClaimableInterests =
                await this.sfWBTC.getClaimableInterests(this.deployer.address);

            await increaseBlock(28800);
            let [, afterBorrowedAmount] = await this.sfWBTC.getAccountSnapshot(
                this.tester.address
            );
            let afterClaimableInterests =
                await this.sfWBTC.getClaimableInterests(this.deployer.address);

            expect(smallNum(afterBorrowedAmount, 6)).to.be.greaterThan(
                smallNum(beforeBorrowedAmount, 6)
            );

            expect(smallNum(afterClaimableInterests, 6)).to.be.greaterThan(
                smallNum(beforeClaimableInterests, 6)
            );
        });

        it("reverts if not insufficient pool to provide interests", async function () {
            await expect(
                this.sfWBTC
                    .connect(this.deployer)
                    .claimInterests(bigNum(10, 18))
            ).to.be.reverted;
        });
    });

    describe("repayBorrow", function () {
        describe("repayBorrow", function () {
            it("reverts if no repayAmount", async function () {
                let [shareAmount, repayAmount] =
                    await this.sfWBTC.getAccountSnapshot(this.tester.address);
                repayAmount = BigInt(repayAmount) * BigInt(2);

                await expect(
                    this.sfWBTC
                        .connect(this.deployer)
                        .repayBorrow(BigInt(repayAmount))
                ).to.be.reverted;
            });

            it("get debt amount", async function () {
                let [shareAmount, beforeRepayAmount] =
                    await this.sfWBTC.getAccountSnapshot(this.tester.address);
                let repayAmount =
                    BigInt(beforeRepayAmount) /
                    BigInt(bigNum(1, 12)) /
                    BigInt(2);
                await this.WBTC.connect(this.deployer).transfer(
                    this.tester.address,
                    BigInt(repayAmount)
                );
                await this.WBTC.connect(this.tester).approve(
                    this.sfWBTC.address,
                    BigInt(repayAmount)
                );
                await this.sfWBTC
                    .connect(this.tester)
                    .repayBorrow(BigInt(repayAmount));

                let [, afterRepayAmount] = await this.sfWBTC.getAccountSnapshot(
                    this.tester.address
                );

                expect(
                    smallNum(
                        BigInt(beforeRepayAmount) - BigInt(afterRepayAmount),
                        18
                    )
                ).to.be.closeTo(smallNum(repayAmount, 8), 0.01);
            });
        });

        describe("claimInterests", function () {
            it("claimInterests and check", async function () {
                let claimableInterests =
                    await this.sfWBTC.getClaimableInterests(
                        this.deployer.address
                    );
                let beforeBal = await this.WBTC.balanceOf(
                    this.deployer.address
                );
                let beforeSuppliedAmount = await this.sfWBTC.getSuppliedAmount(
                    this.deployer.address
                );
                let beforeOwnerBal = await this.WBTC.balanceOf(
                    this.deployer.address
                );

                await this.sfWBTC
                    .connect(this.deployer)
                    .claimInterests(claimableInterests);

                let afterBal = await this.WBTC.balanceOf(this.deployer.address);
                let afterSuppliedAmount = await this.sfWBTC.getSuppliedAmount(
                    this.deployer.address
                );
                let afterOwnerBal = await this.WBTC.balanceOf(
                    this.deployer.address
                );

                let supplierAmount = BigInt(afterBal) - BigInt(beforeBal);
                let ownerAmount =
                    BigInt(afterOwnerBal) - BigInt(beforeOwnerBal);

                expect(smallNum(claimableInterests, 8)).to.be.equal(
                    smallNum(supplierAmount, 8)
                );
                expect(smallNum(beforeSuppliedAmount, 8)).to.be.closeTo(
                    smallNum(afterSuppliedAmount, 8),
                    0.01
                );
            });
        });
    });
});
