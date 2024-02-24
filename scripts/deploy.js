const { ethers } = require("hardhat");
const { erc20_abi } = require("../external_abi/ERC20.abi.json");
const {
  uniswapV2_router,
} = require("../external_abi/UniswapV2Router.abi.json");
const { getDeploymentParam } = require("./params");
const { deploy, deployProxy, getContract } = require("hardhat-libutils");

async function main() {
  let [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account: ", deployer.address);
  let param = getDeploymentParam();
// const SFProtocolToken = await ethers.getContractFactory("SFProtocolToken", deployer);
  let feeRate = {
    borrowingFeeRate: 100, // 1%
    redeemingFeeRate: 100, // 2%
    claimingFeeRate: 50, // 1.5%
  };

  let interestRateModel = await deploy(
    "InterestRateModel",
    "InterestRateModel",
    BigInt(param.interestRate.blocksPerYear),
    BigInt(param.interestRate.baseRatePerYear),
    BigInt(param.interestRate.multiplerPerYear),
    BigInt(param.interestRate.jumpMultiplierPerYear),
    BigInt(param.interestRate.kink),
    deployer.address,
    param.interestRate.name
  );

  let priceOracle = await deploy(
    "PriceOracle",
    "PriceOracle",
    param.HBAR,
    param.dexRouterV2Address
  );

  let marketPositionManager = await deployProxy(
    "MarketPositionManager",
    "MarketPositionManager",
    [priceOracle.address, param.maxLiquidateRate, param.healthcareThresold]
  )
    let USDClending = await deploy("SFProtocolToken", "SFProtocolToken",
        feeRate,
        param.USDC,
        interestRateModel.address,
        marketPositionManager.address,
        param.initialExchangeRateMantissa,
        param.dexRouterV2Address,
        param.HBAR,
        "usdc",
        "usdcl",
    );
    let WBTClending = await deploy("SFProtocolToken", "SFProtocolToken",
        feeRate,
        param.WBTC,
        interestRateModel.address,
        marketPositionManager.address,
        param.initialExchangeRateMantissa,
        param.dexRouterV2Address,
        param.HBAR,
        "wbtc",
        "wbtcl",
    );
    let WETHlending = await deploy("SFProtocolToken", "SFProtocolToken",
        feeRate,
        param.WETH,
        interestRateModel.address,
        marketPositionManager.address,
        param.initialExchangeRateMantissa,
        param.dexRouterV2Address,
        param.HBAR,
        "weth",
        "wethl",
    );
    let HBARlending = await deploy("HBARProtocol", "HBARProtocol",
        feeRate,
        param.HBAR,
        interestRateModel.address,
        marketPositionManager.address,
        param.initialExchangeRateMantissa,
        param.dexRouterV2Address,
        "hbar",
        "hbarl",
    );
    let HBARXlending = await deploy("SFProtocolToken", "SFProtocolToken",
        feeRate,
        param.HBARX,
        interestRateModel.address,
        marketPositionManager.address,
        param.initialExchangeRateMantissa,
        param.dexRouterV2Address,
        param.HBAR,
        "hbarx",
        "hbarxl",
    );

    console.log("Deployed successfully!");

    const marketManager = await ethers.getContractAt("MarketPositionManager", marketPositionManager.address, deployer);
    await marketManager.addToMarket(USDClending.address);
    await marketManager.addToMarket(WBTClending.address);
    await marketManager.addToMarket(WETHlending.address);
    await marketManager.addToMarket(HBARlending.address);
    await marketManager.addToMarket(HBARXlending.address);
    await marketManager.setBorrowCaps([USDClending.address, WBTClending.address, WETHlending.address, HBARlending.address, HBARXlending.address],[77, 78, 80, 60, 58]);
    const usdclendingContract = await ethers.getContractAt("SFProtocolToken", USDClending.address, deployer);
    await usdclendingContract.tokenAssociate(param.USDC);
    const wbtclendingContract = await ethers.getContractAt("SFProtocolToken", WBTClending.address, deployer);
    await wbtclendingContract.tokenAssociate(param.WBTC);
    const wethlendingContract = await ethers.getContractAt("SFProtocolToken", WETHlending.address, deployer);
    await wethlendingContract.tokenAssociate(param.WETH);
    const hbarxlendingContract = await ethers.getContractAt("SFProtocolToken", HBARXlending.address, deployer);
    await hbarxlendingContract.tokenAssociate(param.HBARX);
    console.log("setting environment successfully!");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
