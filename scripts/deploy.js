const { ethers } = require("hardhat");
const { erc20_abi } = require("../external_abi/ERC20.abi.json");
const {
    uniswapV2_router,
} = require("../external_abi/UniswapV2Router.abi.json");
const { bigNum, smallNum, getETHBalance } = require("hardhat-libutils");

async function main() {
    let [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with account: ", deployer.address);
    console.log("Deployed successfully!");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
