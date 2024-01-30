const { expect } = require("chai");
const { ethers } = require("hardhat");
const { deploy, bigNum, smallNum } = require("hardhat-libutils");

const {
    uniswapV2_router,
} = require("../external_abi/UniswapV2Router.abi.json");
const { getDeploymentParam } = require("../scripts/params");

describe("PriceOracle test", function () {
    let params;
    before(async function () {
        [this.deployer, this.account_1] = await ethers.getSigners();

        params = getDeploymentParam();

        this.PriceOracle = await deploy(
            "PriceOracle",
            "PriceOracle",
            params.HBAR,
            params.dexRouterV2Address
        );

        this.dexRouter = new ethers.Contract(
            params.dexRouterV2Address,
            uniswapV2_router,
            this.deployer
        );
    });

    it("check deployment", async function () {
        console.log("deployed successfully!");
    });

    it("check price for WBTC, WETH", async function () {
        let tokens = [params.WBTC, params.WETH];
        let decimals = [6, 6];

        for (let i = 0; i < tokens.length; i++) {
            let amounts = await this.dexRouter.getAmountsOut(
                bigNum(1, decimals[i]),
                [tokens[i], params.HBAR]
            );

            let price = await this.PriceOracle.getTokenPrice(tokens[i]);

            expect(smallNum(amounts[1], 8)).to.be.closeTo(
                smallNum(price, 18),
                0.001
            );
        }
    });

    it("check price for HBAR", async function () {
        let price = await this.PriceOracle.getTokenPrice(params.HBAR);
        expect(smallNum(price, 18)).to.be.closeTo(
            1,
            0.001
        );
    });

    it("updateBaseToken", async function () {
        let tokenAddress = await this.PriceOracle.baseToken();
        expect(tokenAddress).to.be.equal(
            params.HBAR
        );

        // reverts if base token address is invalid
        await expect(
            this.PriceOracle.updateBaseToken(ethers.constants.AddressZero)
        ).to.be.revertedWith("invalid baseToken address");

        // update baseToken and check
        await this.PriceOracle.updateBaseToken(params.USDC);
        expect(await this.PriceOracle.baseToken()).to.be.equal(
            params.USDC
        );

        // reverts if caller is not the owner
        await expect(
            this.PriceOracle.connect(this.account_1).updateBaseToken(
                params.USDC
            )
        ).to.be.reverted;
    });
});
