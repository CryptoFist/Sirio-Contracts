const { ethers } = require("hardhat");
const { deploy } = require("hardhat-libutils");
const { getDeploymentParam } = require("../scripts/params");

describe("PriceOracle test", function () {
    let params;
    before(async function () {
        [this.deployer, this.account_1] = await ethers.getSigners();

        params = getDeploymentParam();

        this.PriceOracle = await deploy(
            "PriceOracle",
            "PriceOracle",
            params.USDCAddress,
            params.dexRouterV2Address
        );
    });

    it("check deployment", async function () {
        console.log("deployed successfully!");
    });
});
