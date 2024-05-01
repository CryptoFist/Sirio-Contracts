/**
 * @type import('hardhat/config').HardhatUserConfig
 */
// require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-contract-sizer");
require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomiclabs/hardhat-ethers");
require("solidity-coverage");
require("dotenv").config();

module.exports = {
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {
            forking: {
                url: `https://mainnet.infura.io/v3/${process.env.ETH_INFURA_ID}`,
                blockNumber: 18761944,
            },
        },
        // Defines the configuration settings for connecting to Hedera testnet
        testnet: {
            // Specifies URL endpoint for Hedera testnet pulled from the .env file
            url: process.env.TESTNET_ENDPOINT,
            // Your ECDSA testnet account private key pulled from the .env file
            accounts: [
                process.env.TESTNET_OPERATOR_PRIVATE_KEY,
                process.env.TESTNET_TESTER_PRIVATE_KEY,
            ],
        },
        mainnet: {
            url: process.env.MAINNET_ENDPOINT,
            chainId: 295,
            accounts: [process.env.MAINNET_OPERATOR_PRIVATE_KEY],
        },
    },
    solidity: {
        compilers: [
            {
                version: "0.8.23",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 2000,
                    },
                },
            },
        ],
    },
    mocha: {
        timeout: 600000,
    },
};
