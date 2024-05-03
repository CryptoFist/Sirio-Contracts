require("dotenv").config();
const { ethers: hardhatEthers } = require("hardhat");
const parameterConfig = require("../parameterConfig.json");
const ethers = require("ethers");
const SFPProtocolTokenABI = require("../internal_abi/SFProtocolToken.json");

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
  const privateKey = parameterConfig.OperatorPrivatKey;
  const sfProtocolContract = parameterConfig.sFProtocolContract;
  const positionManagerContract = parameterConfig.marketPositionManager;
  const positionManagerConfig = parameterConfig.positionManager;
  const configBorrowCaps = parameterConfig.positionManager.borrowCap;

  const client = new ethers.providers.JsonRpcProvider(network);

  const wallet = new ethers.Wallet(privateKey, client);

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

  const feeRate = await sFProtocolContract.feeRate();
  console.log(
    "this is the Fee Rate which is currently beeing used\n",
    `Borrowing feeRate: ${configFees.borrowingFeeRate} \n Redeem feeRate: ${configFees.redeemingFeeRate}\n claiming feeRate: ${configFees.claimingFeeRate}`
  );

  const updatedFees = checkFeeConfig(feeRate, configFees);
  console.log("here we are updating the fee Rate", updatedFees);

  await sFProtocolContract.setFeeRate(updatedFees);

  const feeRateAfter = await sFProtocolContract.feeRate();
  console.log(
    "Double checking that the feeRate has been changed",
    feeRateAfter
  );
  if (parameterConfig.positionManager.runBorrowCap) {
    await marketManager.setBorrowCaps(
      positionManagerConfig.addresses,
      configBorrowCaps
    );
    for (let i = 0; i < positionManagerConfig.addresses.length; i++) {
      const getBorrowCap = await marketManager.borrowCaps(
        positionManagerConfig.addresses[i]
      );
      console.log(
        `token address: ${positionManagerConfig.addresses[i]} new value is set to ${getBorrowCap}`
      );
    }
  }
  if (positionManagerConfig.runLiquidationRate) {
    const getLiquidationRate = await marketManager.maxLiquidateRate();
    console.log("current Liquidation Rate", getLiquidationRate);
    await marketManager.setMaxLiquidateRate(
      positionManagerConfig.liquidateRate
    );
    const updateLiquidationRate = await marketManager.maxLiquidateRate();
    console.log("updated liquidation Rate", updateLiquidationRate);
  }
}

feeAdjustment().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
