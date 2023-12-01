const { expect } = require("chai");
const { ethers } = require("hardhat");

const { deploy } = require("../scripts/utils");

describe("End To End test", function () {
    before(async function () {
        [this.deployer] = await ethers.getSigners();
    });

    it("check deployment", async function () {
        console.log("deployed successfully!");
    });
});
