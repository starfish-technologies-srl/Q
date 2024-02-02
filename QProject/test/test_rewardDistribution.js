const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

describe("Test claim fee functionality", async function () {
  let QContract;
  let forwarder, devAddress, dxnBuyAndBurn, qBuyAndBurn, ai, deployer, ai2;
  beforeEach("Set enviroment", async () => {
    [deployer, forwarder, devAddress, dxnBuyAndBurn, qBuyAndBurn, ai, ai2] =
      await ethers.getSigners();

    const qContract = await ethers.getContractFactory("Q");
    QContract = await qContract.deploy(
      forwarder.address,
      devAddress.address,
      dxnBuyAndBurn.address,
      qBuyAndBurn.address
    );

    await QContract.deployed();
  });

  it("Contribute", async () => {
    await QContract.burnBatch(ai.address, 100, {
      value: ethers.utils.parseEther("100"),
    });
    expect(
      ethers.utils.formatEther(
        await QContract.accCycleBatchesBurned(deployer.address)
      )
    ).to.equal("95.0");
    expect(
      ethers.utils.formatEther(
        await QContract.accCycleBatchesBurned(ai.address)
      )
    ).to.equal("5.0");

    let actualNumberOfInteraction = await QContract.cycleInteraction(
      await QContract.getCurrentCycle()
    );

    let protocolFee =
      (0.01 * 100 * Number(actualNumberOfInteraction) * 101) / 100;

    await QContract.burnBatch(ai.address, 100, {
      value: ethers.utils.parseEther(protocolFee.toString()),
    });

    expect(
      ethers.utils.formatEther(
        await QContract.accCycleBatchesBurned(deployer.address)
      )
    ).to.equal("190.0");
    expect(
      ethers.utils.formatEther(
        await QContract.accCycleBatchesBurned(ai.address)
      )
    ).to.equal("10.0");

    await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24]);
    await hre.ethers.provider.send("evm_mine");

    console.log("Acum");
    await QContract.burnBatch(ai.address, 100, {
      value: ethers.utils.parseEther("100"),
    });
    expect(await QContract.accRewards(deployer.address)).to.equal(
      ethers.utils.parseEther("9500")
    );

    await QContract.connect(ai).burnBatch(ai2.address, 100, {
      value: ethers.utils.parseEther(protocolFee.toString()),
    });

    expect(await QContract.accRewards(ai.address)).to.equal(
      ethers.utils.parseEther("500")
    );
  });
});
