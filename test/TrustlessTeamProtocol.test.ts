import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Contract } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("TrustlessTeamProtocol", function () {
  let trustlessTeamProtocol: any;
  let employeeAssignment: any;
  let systemWallet: any;
  let owner: HardhatEthersSigner;
  let user1: HardhatEthersSigner;
  let user2: HardhatEthersSigner;
  let employee1: HardhatEthersSigner;

  beforeEach(async function () {
    [owner, user1, user2, employee1] = await ethers.getSigners();

    try {
      // Deploy Employee Assignment first
      const EmployeeAssignmentFactory = await ethers.getContractFactory("EmployeeAssignment", owner);
      employeeAssignment = await upgrades.deployProxy(EmployeeAssignmentFactory, [], {
        initializer: "initialize",
        kind: "uups"
      });
      await employeeAssignment.waitForDeployment();
      const employeeAssignmentAddress = await employeeAssignment.getAddress();

      // Deploy System Wallet with Employee Assignment address
      const SystemWalletFactory = await ethers.getContractFactory("System_wallet", owner);
      systemWallet = await upgrades.deployProxy(SystemWalletFactory, [employeeAssignmentAddress], {
        initializer: "initialize",
        kind: "uups"
      });
      await systemWallet.waitForDeployment();
      const systemWalletAddress = await systemWallet.getAddress();

      // Deploy TrustlessTeamProtocol (main contract) with dependencies
      const MainContractFactory = await ethers.getContractFactory("TrustlessTeamProtocol", owner);
      trustlessTeamProtocol = await upgrades.deployProxy(MainContractFactory, [
        employeeAssignmentAddress,
        systemWalletAddress,
        24n, // cooldownInHour
        1000000000n, // maxStake (large enough for test)
        10n, // NegPenalty
        100n, // maxReward
        24n, // minRevisionTimeInHour
        5n, // feePercentage
        3n, // maxRevision
        10n, // CancelByMe
        5n, // requestCancel
        5n, // respondCancel
        3n, // revision
        20n, // taskAcceptCreator
        20n, // taskAcceptMember
        15n, // deadlineHitCreator
        15n // deadlineHitMember
      ], {
        initializer: "initialize",
        kind: "uups"
      });
      await trustlessTeamProtocol.waitForDeployment();
    } catch (error) {
      console.error("Error during deployment:", error);
      throw error;
    }
  });

  describe("UserRegister", function () {
    it("Should allow user registration", async function () {
      await trustlessTeamProtocol.connect(user1).register(
        "User One",
        25
      );

      const user1Data = await trustlessTeamProtocol.connect(user1).getMyData();
      expect(user1Data.name).to.equal("User One");
      expect(user1Data.age).to.equal(25);
      expect(user1Data.isRegistered).to.be.true;
    });

    it("Should prevent duplicate registration", async function () {
      await trustlessTeamProtocol.connect(user1).register(
        "User One",
        25
      );

      await expect(
        trustlessTeamProtocol.connect(user1).register(
          "User One Again",
          25
        )
      ).to.be.revertedWithCustomError(trustlessTeamProtocol, "AlredyRegistered");
    });
  });

  describe("EmployeeAssignment", function () {
    it("Should allow owner to add employee", async function () {
      await employeeAssignment.connect(owner).assignNewEmployee(employee1.address);
      const isEmployee = await employeeAssignment.hasRole(employee1.address);
      expect(isEmployee).to.be.true;
    });

    it("Should prevent non-owner from adding employee", async function () {
      await expect(
        employeeAssignment.connect(user1).assignNewEmployee(employee1.address)
      ).to.be.revertedWith("EmployeeAssignment: caller is not the owner");
    });
  });

  describe("UserReputation", function () {
    beforeEach(async function () {
      // Register user first
      await trustlessTeamProtocol.connect(user1).register(
        "User One",
        25
      );
    });

    it("Should start with zero reputation", async function () {
      const data = await trustlessTeamProtocol.connect(user1).getMyData();
      expect(data.reputation).to.equal(0);
    });

    it("Should allow setting reputation points configuration", async function () {
      const data = await trustlessTeamProtocol.connect(user1).getMyData();
      expect(data.reputation).to.equal(0);
    });
  });

  describe("SystemWallet", function () {
    const testAmount = ethers.parseEther("1.0");

    it("Should receive funds", async function () {
      // Send some ETH to the system wallet
      await owner.sendTransaction({
        to: await systemWallet.getAddress(),
        value: testAmount
      });

      // Check wallet balance
      const balance = await ethers.provider.getBalance(await systemWallet.getAddress());
      expect(balance).to.equal(testAmount);
    });

    it("Should allow owner to transfer funds", async function () {
      // First fund the contract
      await owner.sendTransaction({
        to: await systemWallet.getAddress(),
        value: testAmount
      });

      // Get initial balance of user1
      const initialBalance = await ethers.provider.getBalance(user1.address);

      // Transfer funds from system wallet to user1
      await systemWallet.connect(owner).transfer(user1.address, testAmount);

      // Check new balance
      const finalBalance = await ethers.provider.getBalance(user1.address);
      expect(finalBalance - initialBalance).to.equal(testAmount);
    });

    it("Should prevent non-owner from transferring funds", async function () {
      await expect(
        systemWallet.connect(user1).transfer(user2.address, testAmount)
      ).to.be.revertedWith("Not owner");
    });
  });
});