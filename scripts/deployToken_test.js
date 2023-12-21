const { ethers } = require("hardhat");
const { bigNum, deploy } = require("hardhat-libutils");

async function main() {
    let [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with account: ", deployer.address);
    await deploy("TestERC20", "TestERC20", "Wrapped BTC", "WBTC", 8);
    console.log("Deployed successfully!");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
