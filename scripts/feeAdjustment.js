require("dotenv").config();
const { ethers: hardhatEthers } = require("hardhat");
const parameterConfig = require("../parameterConfig.json");
const ethers = require("ethers");
const SFPProtocolTokenABI = require("../internal_abi/SFProtocolToken.json");
// const marketPositionManagerABI = require("../internal_abi/MarketPositionManager.json");

function checkFeeConfig(currentFeeRates, configFees) {
  const updatedFeeRates = [
    configFees.borrowingFeeRate === "noChange"
      ? currentFeeRates[0]
      : configFees.borrowingFeeRate,
    configFees.redeemingFeeRate === "noChange"
      ? currentFeeRates[1]
      : configFees.redeemingFeeRate,
    configFees.claimingFeeRate === "noChange"
      ? currentFeeRates[2]
      : configFees.claimingFeeRate,
  ];

  return updatedFeeRates;
}

async function feeAdjustment() {
  const configFees = parameterConfig.fees;
  const network = parameterConfig.hederaRpcUrl;
  const address = parameterConfig.OperatorPrivatKey;
  const sfProtocolContract = parameterConfig.sFProtocolContract;
  const positionManagerContract = parameterConfig.marketPositionManager;
  const borrowCap = parameterConfig.positionManager;
  const redeem = configFees.redeemingFeeRate;

  const client = new ethers.providers.JsonRpcProvider(network);

  const wallet = new ethers.Wallet(address, client);

  // connection to the SFProtocolToken smart contract
  const sFProtocolContract = new ethers.Contract(
    sfProtocolContract,
    SFPProtocolTokenABI,
    wallet
  );

  // connection to the MarketPositionManager smart contract
  const marketManager = await hardhatEthers.getContractAt(
    "MarketPositionManager",
    positionManagerContract,
    wallet
  );

  // const martketProtocolContract = new ethers.Contract(
  //   smartContract.marketPositionManager,
  //   marketPositionManagerABI,
  //   wallet
  // );

  const feeRate = await sFProtocolContract.feeRate();
  console.log("this is the Fee Rate which is currently beeing used", feeRate);

  const updatedFees = checkFeeConfig(feeRate, configFees);
  console.log("here we are updating the fee Rate", updatedFees);

  const setFeeRate = await sFProtocolContract.setFeeRate(updatedFees);
  console.log(" setting the new feeRate:", setFeeRate);

  const feeRateAfter = await sFProtocolContract.feeRate();
  console.log(
    "Double checking that the feeRate has been changed",
    feeRateAfter
  );

  // const setBorrowCap = await marketManager.setBorrowCaps(
  //   ["fad9d6ddc2f5e908b2bdb683728dc83b721d355e4e46fd798d2f2b8e687164ff"],
  //   [300]
  // );
  // console.log("here we can set the borrowing cap", setBorrowCap);

  // const setMaxLiquidateRate = await marketManager.setMaxLiquidateRate(175);
  // console.log("setting the max LiquidateRate", setMaxLiquidateRate);
}

feeAdjustment().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
