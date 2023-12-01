const { ethers, upgrades, network } = require("hardhat");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");
const fs = require("fs");
const { mine } = require("@nomicfoundation/hardhat-network-helpers");

const second = 1;
const minute = 60 * second;
const hour = 60 * minute;
const day = 24 * hour;
const week = 7 * day;
const month = 30 * day;
const year = 365 * day;

const checkRootPath = async () => {
    const addressDir = `${__dirname}/../deploy_address`;
    if (!fs.existsSync(addressDir)) {
        fs.mkdirSync(addressDir);
    }
};

const updateAddress = async (contractName, contractAddreses) => {
    if (network.name == "localhost" || network.name == "hardhat") return;
    await checkRootPath();
    const addressDir = `${__dirname}/../deploy_address/${network.name}`;
    if (!fs.existsSync(addressDir)) {
        fs.mkdirSync(addressDir);
    }

    let data = "";
    if (contractAddreses.length == 2) {
        data = {
            contract: contractAddreses[0],
            proxyImp: contractAddreses[1],
        };
    } else {
        data = {
            contract: contractAddreses[0],
        };
    }

    fs.writeFileSync(
        `${addressDir}/${contractName}.txt`,
        JSON.stringify(data, null, 2)
    );
};

const getContractAddress = async (
    contractName,
    network_name = network.name
) => {
    const addressDir = `${__dirname}/../deploy_address/${network_name}`;
    if (!fs.existsSync(addressDir)) {
        return "";
    }

    let data = fs.readFileSync(`${addressDir}/${contractName}.txt`);
    data = JSON.parse(data, null, 2);

    return data;
};

const getContract = async (
    contractName,
    contractMark,
    network_name = network.name
) => {
    const addressDir = `${__dirname}/../deploy_address/${network_name}`;
    const filePath = `${addressDir}/${contractMark}.txt`;
    if (!fs.existsSync(filePath)) {
        return "";
    }

    let data = fs.readFileSync(filePath);
    data = JSON.parse(data, null, 2);
    // const factory = await ethers.getContractFactory(contractName)
    // await upgrades.forceImport(data.contract,factory)

    return await getAt(contractName, data.contract);
};

const getContractFactory = async (contractName) => {
    return await ethers.getContractFactory(contractName);
};

const deploy = async (contractName, contractMark, ...args) => {
    const factory = await getContractFactory(contractName);
    const contract = await factory.deploy(...args);
    await contract.deployed();
    if (network.name != "hardhat") {
        await verify(contract.address, [...args]);
    }
    console.log(contractMark, contract.address);
    await updateAddress(contractMark, [contract.address]);
    return contract;
};

const deployProxy = async (contractName, contractMark, args = []) => {
    const factory = await getContractFactory(contractName);
    const contract = await upgrades.deployProxy(factory, args, {
        unsafeAllow: ["delegatecall", "constructor"],
    });
    // const contract = await upgrades.deployProxy(factory, args);
    await contract.deployed();
    const implAddress = await getImplementationAddress(
        ethers.provider,
        contract.address
    );
    if (network.name != "hardhat") {
        await verify(implAddress, args);
    }
    await updateAddress(contractMark, [contract.address, implAddress]);
    console.log(contractMark, contract.address, implAddress);
    return contract;
};

const verifyProxy = async (contractName, contractMark, args = []) => {
    const contract = await getContract(
        contractName,
        contractMark,
        network.name
    );

    const implAddress = await getImplementationAddress(
        ethers.provider,
        contract.address
    );
    await verify(implAddress, args);
};

const upgradeProxyWithAddress = async (
    contractName,
    oldContract,
    network_name = network.name
) => {
    const contractAddress = oldContract.address;
    const factory = await ethers.getContractFactory(contractName);
    try {
        await upgrades.forceImport(contractAddress, factory);
    } catch (ex) {}
    const contract = await upgrades.upgradeProxy(contractAddress, factory, {
        unsafeAllow: ["delegatecall", "constructor"],
    });
    await contract.deployed();
    const implAddress = await getImplementationAddress(
        ethers.provider,
        contract.address
    );
    console.log(contractName, contract.address, implAddress);
    return contract;
};

const upgradeProxy = async (
    contractName,
    contractMark,
    network_name = network.name
) => {
    const oldContract = await getContract(
        contractName,
        contractMark,
        network_name
    );
    const contractAddress = oldContract.address;
    const factory = await ethers.getContractFactory(contractName);
    try {
        await upgrades.forceImport(contractAddress, factory);
    } catch (ex) {}
    const contract = await upgrades.upgradeProxy(contractAddress, factory, {
        unsafeAllow: ["delegatecall", "constructor"],
    });
    await contract.deployed();
    const implAddress = await getImplementationAddress(
        ethers.provider,
        contract.address
    );
    await updateAddress(contractMark, [contract.address, implAddress]);
    console.log(contractName, contract.address, implAddress);
    return contract;
};

const getOrDeploy = async (contractName, contractMark, ...args) => {
    let contract = await getContract(contractName, contractMark, network.name);
    if (contract) {
        log(`${contractMark} already deployed at ${contract.address}`);
    } else {
        contract = await deploy(contractName, contractMark, ...args);
        log(`Deployed ${contractMark} at ${contract.address}`);
    }
    return contract;
};

const getOrDeployProxy = async (contractName, contractMark, args = []) => {
    let contract = await getContract(contractName, contractMark, network.name);

    if (contract) {
        log(`${contractMark} already deployed at ${contract.address}`);
    } else {
        contract = await deployProxy(contractName, contractMark, args);
        log(`Deployed ${contractMark} at ${contract.address}`);
    }
    return contract;
};

const getAt = async (contractName, contractAddress) => {
    return await ethers.getContractAt(contractName, contractAddress);
};

const verify = async (contractAddress, args = []) => {
    if (network == "localhost" || network == "hardhat") return;
    try {
        await hre.run("verify:verify", {
            address: contractAddress,
            constructorArguments: args,
        });
        console.log(`Verified ${contractAddress} with args ${args}`);
    } catch (ex) {
        log(`Error: ${ex}`);
    }
};

const spendTime = async (spendSeconds) => {
    await network.provider.send("evm_increaseTime", [spendSeconds]);
    await network.provider.send("evm_mine");
};

const increaseBlock = async (blockCnt) => {
    await mine(blockCnt);
};

const getETHBalance = async (walletAddress) => {
    return await ethers.provider.getBalance(walletAddress);
};

const sendETHTo = async (from, to, amount) => {
    await from.sendTransaction({
        to: to.address,
        value: BigInt(amount),
    });
};

const getCurrentTimestamp = async () => {
    return (await ethers.provider.getBlock("latest")).timestamp;
};

const log = (message) => {
    console.log(`[${network.name}][${Date.now().toString()}] ${message}`);
};

const bigNum = (num, decimals = 18) => num + "0".repeat(decimals);

const smallNum = (num, decimals = 18) => parseInt(num) / bigNum(1, decimals);

module.exports = {
    getAt,
    deploy,
    deployProxy,
    upgradeProxy,
    upgradeProxyWithAddress,
    getContractFactory,
    getContractAddress,
    getContract,
    getOrDeploy,
    getOrDeployProxy,
    verify,
    verifyProxy,
    spendTime,
    increaseBlock,
    getETHBalance,
    sendETHTo,
    getCurrentTimestamp,
    log,
    smallNum,
    bigNum,
    second,
    minute,
    hour,
    day,
    week,
    month,
    year,
};
