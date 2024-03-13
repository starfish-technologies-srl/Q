const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

describe("Test AIRegister function", async function () {
  let deployer, forwarder, devAddress, dxnBuyAndBurn, QPayment;
  beforeEach("Set enviroment", async () => {
    [deployer, forwarder, devAddress, dxnBuyAndBurn] = await ethers.getSigners();

    const qPayment = await ethers.getContractFactory("QPayment");
    QPayment = await qPayment.deploy();
    await QPayment.deployed();
  });

  it("AIRegister function", async () => {
    console.log(QPayment.address);
  });

});
