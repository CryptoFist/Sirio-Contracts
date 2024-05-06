const { ethers } = require("hardhat");
const { getDeploymentParam } = require("./params");
const {
    deploy,
    deployProxy,
    getContract,
    smallNum,
} = require("hardhat-libutils");
const { erc20_abi } = require("../external_abi/ERC20.abi.json");
const protocolABI = require("../internal_abi/SFProtocolToken.json");
const marketPositionManagerABI = require("../internal_abi/MarketPositionManager.json");

async function setEnvironment() {
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
        [priceOracle.address, param.maxLiquidateRate]
    );

    //   const deploy_token = await SFProtocolToken.deploy(
    //     feeRate,
    //     "0x00000000000000000000000000000000007502DB",
    //     "0x12c047Ff5A091dA9596E3dB69EBA18CADA9b2aAb",
    //     "0x45f816ef892a6523A8B611E3bBaBB799387F40b9",
    //     ethers.utils.parseUnits("0.02"),
    //     "eth",
    //     "ethl",
    //   );
    //     const contractAddress = (await deploy_token.deployTransaction.wait()).contractAddress;
    let USDClending = await deploy(
        "SFProtocolToken",
        "SFProtocolToken",
        feeRate,
        param.USDC,
        interestRateModel.address,
        marketPositionManager.address,
        param.initialExchangeRateMantissa,
        "usdc",
        "usdcl"
    );
    let WBTClending = await deploy(
        "SFProtocolToken",
        "SFProtocolToken",
        feeRate,
        param.WBTC,
        interestRateModel.address,
        marketPositionManager.address,
        param.initialExchangeRateMantissa,
        "wbtc",
        "wbtcl"
    );
    let WETHlending = await deploy(
        "SFProtocolToken",
        "SFProtocolToken",
        feeRate,
        param.WETH,
        interestRateModel.address,
        marketPositionManager.address,
        param.initialExchangeRateMantissa,
        "weth",
        "wethl"
    );
    let HBARlending = await deploy(
        "HBARProtocol",
        "HBARProtocol",
        feeRate,
        param.HBAR,
        interestRateModel.address,
        marketPositionManager.address,
        param.initialExchangeRateMantissa,
        "hbar",
        "hbarl"
    );
    let HBARXlending = await deploy(
        "SFProtocolToken",
        "SFProtocolToken",
        feeRate,
        param.HBARX,
        interestRateModel.address,
        marketPositionManager.address,
        param.initialExchangeRateMantissa,
        "hbarx",
        "hbarxl"
    );

    console.log("Deployed successfully!");

    const marketManager = await ethers.getContractAt(
        "MarketPositionManager",
        marketPositionManager.address,
        deployer
    );
    await marketManager.addToMarket(USDClending.address);
    await marketManager.addToMarket(WBTClending.address);
    await marketManager.addToMarket(WETHlending.address);
    await marketManager.addToMarket(HBARlending.address);
    await marketManager.addToMarket(HBARXlending.address);
    await marketManager.setBorrowCaps(
        [
            USDClending.address,
            WBTClending.address,
            WETHlending.address,
            HBARlending.address,
            HBARXlending.address,
        ],
        [77, 78, 80, 60, 58]
    );
    const usdclendingContract = await ethers.getContractAt(
        "SFProtocolToken",
        USDClending.address,
        deployer
    );
    await usdclendingContract.tokenAssociate(param.USDC);
    const wbtclendingContract = await ethers.getContractAt(
        "SFProtocolToken",
        WBTClending.address,
        deployer
    );
    await wbtclendingContract.tokenAssociate(param.WBTC);
    const wethlendingContract = await ethers.getContractAt(
        "SFProtocolToken",
        WETHlending.address,
        deployer
    );
    await wethlendingContract.tokenAssociate(param.WETH);
    // const lendingContract = await ethers.getContractAt("SFProtocolToken", WBTClending.address, deployer);
    // await wbtclendingContract.tokenAssociate(param.WBTC);
    const hbarxlendingContract = await ethers.getContractAt(
        "SFProtocolToken",
        HBARXlending.address,
        deployer
    );
    await hbarxlendingContract.tokenAssociate(param.HBARX);
    console.log("setting environment successfully!");
}

async function testBorrow() {
    const [deployer] = await ethers.getSigners();
    let protocolAddress = "0x328019079e4682d2f0284f771aab89cb9e34d8d8";
    let protocol = new ethers.Contract(protocolAddress, protocolABI, deployer);
    let marketPositionManagerAddress = await protocol.marketPositionManager();
    let marketPositionManager = new ethers.Contract(
        marketPositionManagerAddress,
        marketPositionManagerABI,
        deployer
    );

    let borrower = "0x2e1af666c48a13e0f71c4affc963d087690f6885";
    let suppliedAmount = await protocol.getSuppliedAmount(borrower);
    console.log(await marketPositionManager.checkListedToken(protocolAddress));
    console.log(
        await marketPositionManager.borrowGuardianPaused(protocolAddress)
    );

    console.log(smallNum(suppliedAmount, 8));

    let underlyingBalance = await protocol.getUnderlyingBalance();
    console.log(smallNum(underlyingBalance, 8));

    let underlyingTokenAddress = await protocol.underlyingToken();
    let underlyingToken = new ethers.Contract(
        underlyingTokenAddress,
        erc20_abi,
        deployer
    );
    let underlyingDecimals = await underlyingToken.decimals();
    console.log(underlyingDecimals);
}

async function main() {
    // await setEnvironment();
    await testBorrow();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
