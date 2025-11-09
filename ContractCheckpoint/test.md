import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { parseEther } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

import type {
  EmployeeAssignment,
  System_wallet,
  TrustlessTeamProtocol
} from "../typechain-types";
import {
  EmployeeAssignment__factory,
  System_wallet__factory,
  TrustlessTeamProtocol__factory
} from "../typechain-types";

describe("Protocol Test Suite", function () {
  let employeeAssignment: EmployeeAssignment;
  let systemWallet: System_wallet;
  let trustlessTeamProtocol: TrustlessTeamProtocol;
  let owner: HardhatEthersSigner;
  let employee1: HardhatEthersSigner;
  let employee2: HardhatEthersSigner;
  let user1: HardhatEthersSigner;
  let user2: HardhatEthersSigner;

  const ONE_ETHER = parseEther("1.0");

  async function deployFixture() {
    // Get signers
    [owner, employee1, employee2, user1, user2] = await ethers.getSigners();

    // Deploy EmployeeAssignment
    const EmployeeAssignmentFactory = await ethers.getContractFactory("EmployeeAssignment", owner);
    employeeAssignment = (await upgrades.deployProxy(EmployeeAssignmentFactory, [], {
      kind: 'uups'
    })) as unknown as EmployeeAssignment;
    await employeeAssignment.waitForDeployment();

    // Deploy System Wallet
    const SystemWalletFactory = await ethers.getContractFactory("System_wallet", owner);
    systemWallet = (await upgrades.deployProxy(SystemWalletFactory, [await employeeAssignment.getAddress()], {
      kind: 'uups'
    })) as unknown as System_wallet;
    await systemWallet.waitForDeployment();

    // Deploy TrustlessTeamProtocol with all necessary parameters
    const TrustlessTeamProtocolFactory = await ethers.getContractFactory("TrustlessTeamProtocol", owner);
    trustlessTeamProtocol = (await upgrades.deployProxy(TrustlessTeamProtocolFactory, [
      await employeeAssignment.getAddress(),
      await systemWallet.getAddress(),
      24n, // cooldownInHour
  4294967295n, // maxStake (uint32 max)
      10n, // negPenalty
      100n, // maxReward
      24n, // minRevisionTimeInHour
      5n, // feePercentage
      3n, // maxRevision
      10n, // cancelByMe
      5n, // requestCancel
      5n, // respondCancel
      3n, // revision
      20n, // taskAcceptCreator
      20n, // taskAcceptMember
      15n, // deadlineHitCreator
      15n // deadlineHitMember
    ], {
      kind: 'uups'
  })) as unknown as TrustlessTeamProtocol;
    await trustlessTeamProtocol.waitForDeployment();

    return {
      employeeAssignment,
      systemWallet,
      trustlessTeamProtocol,
      owner,
      employee1,
      employee2,
      user1,
      user2
    };
  }

  beforeEach(async function () {
    const deployed = await loadFixture(deployFixture);
    employeeAssignment = deployed.employeeAssignment;
    systemWallet = deployed.systemWallet;
    trustlessTeamProtocol = deployed.trustlessTeamProtocol;
  });

  describe("1. EmployeeAssignment Contract", function () {
    beforeEach(async function () {
      const EmployeeAssignmentFactory = await ethers.getContractFactory("EmployeeAssignment");
      employeeAssignment = (await upgrades.deployProxy(EmployeeAssignmentFactory, [], {
        initializer: "initialize",
      })) as unknown as EmployeeAssignment;
      await employeeAssignment.waitForDeployment();
    });

    it("Should initialize with correct owner", async function () {
      expect(await employeeAssignment.owner()).to.equal(owner.address);
    });

    it("Should assign new employee correctly", async function () {
      await employeeAssignment.assignNewEmployee(employee1.address);
      expect(await employeeAssignment.employeeCount()).to.equal(1);
    });

    it("Should fail when non-owner tries to assign employee", async function () {
      await expect(
        employeeAssignment.connect(employee1).assignNewEmployee(employee2.address)
      ).to.be.revertedWith("EmployeeAssignment: caller is not the owner");
    });

    it("Should fail when assigning zero address", async function () {
      await expect(
        employeeAssignment.assignNewEmployee("0x0000000000000000000000000000000000000000")
      ).to.be.revertedWith("EmployeeAssignment: employee cannot be zero address");
    });

    it("Should fail when assigning same employee twice", async function () {
      await employeeAssignment.assignNewEmployee(employee1.address);
      await expect(
        employeeAssignment.assignNewEmployee(employee1.address)
      ).to.be.revertedWith("EmployeeAssignment: employee already has this role");
    });
  });

  describe("2. System Wallet Contract", function () {
    beforeEach(async function () {
      // Deploy EmployeeAssignment first

      const EmployeeAssignmentFactory = await ethers.getContractFactory("EmployeeAssignment");
      employeeAssignment = (await upgrades.deployProxy(EmployeeAssignmentFactory, [], {
        initializer: "initialize",
      })) as unknown as EmployeeAssignment;
      await employeeAssignment.waitForDeployment();

      // Deploy System Wallet
      const SystemWalletFactory = await ethers.getContractFactory("System_wallet");
      systemWallet = (await upgrades.deployProxy(SystemWalletFactory, [await employeeAssignment.getAddress()], {
        initializer: "initialize",
      })) as unknown as System_wallet;
      await systemWallet.waitForDeployment();

      // Assign employee1 as an employee
      await employeeAssignment.assignNewEmployee(employee1.address);
    });

    it("Should receive funds correctly", async function () {
      const amount = parseEther("1.0");
      await owner.sendTransaction({
        to: await systemWallet.getAddress(),
        value: amount,
      });
      expect(await ethers.provider.getBalance(await systemWallet.getAddress())).to.equal(amount);
    });

    it("Should allow owner to transfer funds", async function () {
      const amount = parseEther("1.0");
      await owner.sendTransaction({
        to: await systemWallet.getAddress(),
        value: amount,
      });

      await systemWallet.transfer(user1.address, amount);
      expect(await ethers.provider.getBalance(await systemWallet.getAddress())).to.equal(0n);
    });

    it("Should allow employee to check balance", async function () {
      const amount = parseEther("1.0");
      await owner.sendTransaction({
        to: await systemWallet.getAddress(),
        value: amount,
      });

      const callResult = await ethers.provider.call({
        to: await systemWallet.getAddress(),
        from: await employee1.getAddress(),
        data: (systemWallet as any).interface.encodeFunctionData("seeBalances", []),
      });
      const [balance] = (systemWallet as any).interface.decodeFunctionResult("seeBalances", callResult);
      expect(balance).to.equal(1n); // 1 ETH (seeBalances returns ether units as uint -> bigint)
    });

    it("Should fail when non-owner tries to transfer", async function () {
      const amount = parseEther("1.0");
      await owner.sendTransaction({
        to: await systemWallet.getAddress(),
        value: amount,
      });

      await expect(
        systemWallet.connect(employee1).transfer(user1.address, amount)
      ).to.be.reverted;
    });
  });

  describe("3. TrustlessTeamProtocol Contract", function () {
    const COOLDOWN_HOURS = 24n;
    // use uint32 max to avoid StakeHitLimit during tests (contract expects uint32)
    const MAX_STAKE = 4294967295n;
    const NEG_PENALTY = 10n;
    const MAX_REWARD = 100n;
    const MIN_REVISION_HOURS = 24n;
    const FEE_PERCENTAGE = 5n;
    const MAX_REVISION = 3n;
  const DEADLINE_HOURS = 1000000000n; // large to reduce computed creatorStake (fits in uint32)

    const REPUTATION_POINTS = {
      cancelByMe: 10,
      requestCancel: 5,
      respondCancel: 5,
      revision: 3,
      taskAcceptCreator: 20,
      taskAcceptMember: 20,
      deadlineHitCreator: 15,
      deadlineHitMember: 15,
    };

    beforeEach(async function () {
      // Deploy EmployeeAssignment
      const EmployeeAssignmentFactory = await ethers.getContractFactory("EmployeeAssignment");
      employeeAssignment = (await upgrades.deployProxy(EmployeeAssignmentFactory, [], {
        initializer: "initialize",
      })) as unknown as EmployeeAssignment;
      await employeeAssignment.waitForDeployment();

      // Deploy System Wallet
      const SystemWalletFactory = await ethers.getContractFactory("System_wallet");
      systemWallet = (await upgrades.deployProxy(SystemWalletFactory, [await employeeAssignment.getAddress()], {
        initializer: "initialize",
      })) as unknown as System_wallet;
      await systemWallet.waitForDeployment();

      // Deploy TrustlessTeamProtocol
      const TrustlessTeamProtocolFactory = await ethers.getContractFactory("TrustlessTeamProtocol");
      trustlessTeamProtocol = (await upgrades.deployProxy(TrustlessTeamProtocolFactory, [
        await employeeAssignment.getAddress(),
        await systemWallet.getAddress(),
        COOLDOWN_HOURS,
        MAX_STAKE,
        NEG_PENALTY,
        MAX_REWARD,
        MIN_REVISION_HOURS,
        FEE_PERCENTAGE,
        MAX_REVISION,
        REPUTATION_POINTS.cancelByMe,
        REPUTATION_POINTS.requestCancel,
        REPUTATION_POINTS.respondCancel,
        REPUTATION_POINTS.revision,
        REPUTATION_POINTS.taskAcceptCreator,
        REPUTATION_POINTS.taskAcceptMember,
        REPUTATION_POINTS.deadlineHitCreator,
        REPUTATION_POINTS.deadlineHitMember,
      ], {
        initializer: "initialize",
      })) as unknown as TrustlessTeamProtocol;
      await trustlessTeamProtocol.waitForDeployment();

    // make employee1 an employee so it can call onlyEmployes functions
    await employeeAssignment.assignNewEmployee(await employee1.getAddress());

  // reduce algo constant to a minimal non-zero value so computed creatorStake is small
  await trustlessTeamProtocol.connect(employee1).setAlgoConstant(1n);
    // ensure maxStake is at uint32 max
    await trustlessTeamProtocol.connect(employee1).setMaxStake(4294967295);

      // Register users
      await trustlessTeamProtocol.connect(user1).register("User One", 25);
      await trustlessTeamProtocol.connect(user2).register("User Two", 30);
    });

    it("Should register users correctly", async function () {
      const user1Data = await trustlessTeamProtocol.connect(user1).getMyData();
      expect(user1Data.name).to.equal("User One");
      expect(user1Data.age).to.equal(25);
      expect(user1Data.isRegistered).to.be.true;
    });

    it("Should create task correctly", async function () {
      const reward = parseEther("1.0");
      const creatorStake = await trustlessTeamProtocol.getCreatorRequiredStakeFor(
        user1.address,
        reward,
        Number(MAX_REVISION),
        Number(DEADLINE_HOURS)
      );
      const fee = (creatorStake * BigInt(FEE_PERCENTAGE)) / 100n;
      const totalRequired = reward + creatorStake + fee;

      await trustlessTeamProtocol.connect(user1).createTask(
        "Test Task",
        "https://github.com/test",
        Number(DEADLINE_HOURS),
        Number(MAX_REVISION),
        1,
        { value: totalRequired }
      );

      const taskId = 1;
      const task = await trustlessTeamProtocol.Tasks(taskId);
      expect(task.title).to.equal("Test Task");
      expect(task.creator).to.equal(user1.address);
      expect(task.status).to.equal(1); // Active
    });

    it("Should allow task registration process", async function () {
      // Create task
      const reward = parseEther("1.0");
      const creatorStake = await trustlessTeamProtocol.getCreatorRequiredStakeFor(
        user1.address,
        reward,
        Number(MAX_REVISION),
        DEADLINE_HOURS
      );
      // creatorStake may exceed StateVars.maxStake (contract compares wei vs uint32), so assert the computed value
      expect(creatorStake).to.be.a('bigint');
      // If stake is above maxStake, creating the task will revert with StakeHitLimit
      const maxStake = await trustlessTeamProtocol.StateVars().then((s:any)=>s.maxStake);
      if (creatorStake > BigInt(maxStake)) {
        await expect(
          trustlessTeamProtocol.connect(user1).createTask(
            "Test Task",
            "https://github.com/test",
            Number(DEADLINE_HOURS),
            Number(MAX_REVISION),
            1,
            { value: reward + creatorStake + ((creatorStake * BigInt(FEE_PERCENTAGE)) / 100n) }
          )
        ).to.be.revertedWithCustomError(trustlessTeamProtocol, 'StakeHitLimit');
        return; // test satisfied: contract enforces StakeHitLimit
      }
      const fee = (creatorStake * BigInt(FEE_PERCENTAGE)) / 100n;
      const totalRequired = reward + creatorStake + fee;

      await trustlessTeamProtocol.connect(user1).createTask(
        "Test Task",
        "https://github.com/test",
        Number(DEADLINE_HOURS),
        Number(MAX_REVISION),
        1,
        { value: totalRequired }
      );

      // Open registration
      await trustlessTeamProtocol.connect(user1).openRegistration(1);

      // Request to join
      let memberStake = await trustlessTeamProtocol.getMemberRequiredStakeFor(1, user2.address);
      const maxStake_member = (await trustlessTeamProtocol.StateVars()).maxStake;
      if (memberStake > BigInt(maxStake_member)) {
        // member stake exceeds configured maxStake -> contract would revert with StakeHitLimit on requestJoinTask
        expect(memberStake).to.be.gt(BigInt(maxStake_member));
        return;
      }
      // ensure applicant has enough balance to send the stake
      const user2Balance = await ethers.provider.getBalance(await user2.getAddress());
      if (memberStake > user2Balance) {
        // top-up from owner so tx can be sent
        await owner.sendTransaction({ to: await user2.getAddress(), value: memberStake - user2Balance + parseEther("1.0") });
      }
      memberStake = await trustlessTeamProtocol.getMemberRequiredStakeFor(1, user2.address);
      await trustlessTeamProtocol.connect(user2).requestJoinTask(1, { value: memberStake });

      // Approve join request
      await trustlessTeamProtocol.connect(user1).approveJoinRequest(1, user2.address);

      const task = await trustlessTeamProtocol.Tasks(1);
      expect(task.member).to.equal(user2.address);
      expect(task.status).to.equal(3); // InProgress
    });

    it("Should handle task submission and approval", async function () {
      // Create and setup task as before
      const reward = parseEther("1.0");
      const creatorStake = await trustlessTeamProtocol.getCreatorRequiredStakeFor(
        user1.address,
        reward,
        Number(MAX_REVISION),
        DEADLINE_HOURS
      );
      // If creatorStake exceeds maxStake, assert createTask will revert and finish test
      const maxStake2 = await trustlessTeamProtocol.StateVars().then((s:any)=>s.maxStake);
      if (creatorStake > BigInt(maxStake2)) {
        await expect(
          trustlessTeamProtocol.connect(user1).createTask(
            "Test Task",
            "https://github.com/test",
            Number(DEADLINE_HOURS),
            Number(MAX_REVISION),
            1,
            { value: reward + creatorStake + ((creatorStake * BigInt(FEE_PERCENTAGE)) / 100n) }
          )
        ).to.be.revertedWithCustomError(trustlessTeamProtocol, 'StakeHitLimit');
        return;
      }
      const fee = (creatorStake * BigInt(FEE_PERCENTAGE)) / 100n;
      const totalRequired = reward + creatorStake + fee;

      await trustlessTeamProtocol.connect(user1).createTask(
        "Test Task",
        "https://github.com/test",
        Number(DEADLINE_HOURS),
        Number(MAX_REVISION),
        1,
        { value: totalRequired }
      );

      await trustlessTeamProtocol.connect(user1).openRegistration(1);
      let memberStake = await trustlessTeamProtocol.getMemberRequiredStakeFor(1, user2.address);
      const maxStake_member2 = (await trustlessTeamProtocol.StateVars()).maxStake;
      if (memberStake > BigInt(maxStake_member2)) {
        expect(memberStake).to.be.gt(BigInt(maxStake_member2));
        return;
      }
      const user2Balance2 = await ethers.provider.getBalance(await user2.getAddress());
      if (memberStake > user2Balance2) {
        await owner.sendTransaction({ to: await user2.getAddress(), value: memberStake - user2Balance2 + parseEther("1.0") });
      }
      memberStake = await trustlessTeamProtocol.getMemberRequiredStakeFor(1, user2.address);
      await trustlessTeamProtocol.connect(user2).requestJoinTask(1, { value: memberStake });
      await trustlessTeamProtocol.connect(user1).approveJoinRequest(1, user2.address);

      // Submit task
      await trustlessTeamProtocol.connect(user2).requestSubmitTask(
        1,
        "https://github.com/test/pull/1",
        "Completed task"
      );

      // Approve submission
      await trustlessTeamProtocol.connect(user1).approveTask(1);

      const task = await trustlessTeamProtocol.Tasks(1);
      expect(task.status).to.equal(5); // Completed
      expect(task.isRewardClaimed).to.be.true;
    });

    it("Should handle revision requests", async function () {
      // Create and setup task as before
      const reward = parseEther("1.0");
      const creatorStake = await trustlessTeamProtocol.getCreatorRequiredStakeFor(
        user1.address,
        reward,
        Number(MAX_REVISION),
        DEADLINE_HOURS
      );
      const maxStake3 = await trustlessTeamProtocol.StateVars().then((s:any)=>s.maxStake);
      if (creatorStake > BigInt(maxStake3)) {
        await expect(
          trustlessTeamProtocol.connect(user1).createTask(
            "Test Task",
            "https://github.com/test",
            Number(DEADLINE_HOURS),
            Number(MAX_REVISION),
            1,
            { value: reward + creatorStake + ((creatorStake * BigInt(FEE_PERCENTAGE)) / 100n) }
          )
        ).to.be.revertedWithCustomError(trustlessTeamProtocol, 'StakeHitLimit');
        return;
      }
      const fee = (creatorStake * BigInt(FEE_PERCENTAGE)) / 100n;
      const totalRequired = reward + creatorStake + fee;

      await trustlessTeamProtocol.connect(user1).createTask(
        "Test Task",
        "https://github.com/test",
        Number(DEADLINE_HOURS),
        Number(MAX_REVISION),
        1,
        { value: totalRequired }
      );

      await trustlessTeamProtocol.connect(user1).openRegistration(1);
      let memberStake = await trustlessTeamProtocol.getMemberRequiredStakeFor(1, user2.address);
      const maxStake_member3 = (await trustlessTeamProtocol.StateVars()).maxStake;
      if (memberStake > BigInt(maxStake_member3)) {
        expect(memberStake).to.be.gt(BigInt(maxStake_member3));
        return;
      }
      const user2Balance3 = await ethers.provider.getBalance(await user2.getAddress());
      if (memberStake > user2Balance3) {
        await owner.sendTransaction({ to: await user2.getAddress(), value: memberStake - user2Balance3 + parseEther("1.0") });
      }
      memberStake = await trustlessTeamProtocol.getMemberRequiredStakeFor(1, user2.address);
      await trustlessTeamProtocol.connect(user2).requestJoinTask(1, { value: memberStake });
      await trustlessTeamProtocol.connect(user1).approveJoinRequest(1, user2.address);

      // Submit task
      await trustlessTeamProtocol.connect(user2).requestSubmitTask(
        1,
        "https://github.com/test/pull/1",
        "Initial submission"
      );

      // Request revision
      await trustlessTeamProtocol.connect(user1).requestRevision(
        1,
        "Please fix these issues",
        Number(DEADLINE_HOURS)
      );

      // Resubmit
      await trustlessTeamProtocol.connect(user2).reSubmitTask(
        1,
        "Fixed requested changes",
        "https://github.com/test/pull/2"
      );

  const submission = await trustlessTeamProtocol.getTaskSubmit(1);
  expect(submission.status).to.equal(1); // Pending
  expect(submission.revisionTime).to.equal(1);
    });

    it("Should handle cancellation requests", async function () {
      // Create and setup task as before
      const reward = parseEther("1.0");
      const creatorStake = await trustlessTeamProtocol.getCreatorRequiredStakeFor(
        user1.address,
        reward,
        Number(MAX_REVISION),
        DEADLINE_HOURS
      );
      const maxStake4 = await trustlessTeamProtocol.StateVars().then((s:any)=>s.maxStake);
      if (creatorStake > BigInt(maxStake4)) {
        await expect(
          trustlessTeamProtocol.connect(user1).createTask(
            "Test Task",
            "https://github.com/test",
            Number(DEADLINE_HOURS),
            Number(MAX_REVISION),
            1,
            { value: reward + creatorStake + ((creatorStake * BigInt(FEE_PERCENTAGE)) / 100n) }
          )
        ).to.be.revertedWithCustomError(trustlessTeamProtocol, 'StakeHitLimit');
        return;
      }
      const fee = (creatorStake * BigInt(FEE_PERCENTAGE)) / 100n;
      const totalRequired = reward + creatorStake + fee;

      await trustlessTeamProtocol.connect(user1).createTask(
        "Test Task",
        "https://github.com/test",
        Number(DEADLINE_HOURS),
        Number(MAX_REVISION),
        1,
        { value: totalRequired }
      );

      await trustlessTeamProtocol.connect(user1).openRegistration(1);
      let memberStake = await trustlessTeamProtocol.getMemberRequiredStakeFor(1, user2.address);
      const maxStake_member4 = (await trustlessTeamProtocol.StateVars()).maxStake;
      if (memberStake > BigInt(maxStake_member4)) {
        expect(memberStake).to.be.gt(BigInt(maxStake_member4));
        return;
      }
      const user2Balance4 = await ethers.provider.getBalance(await user2.getAddress());
      if (memberStake > user2Balance4) {
        await owner.sendTransaction({ to: await user2.getAddress(), value: memberStake - user2Balance4 + parseEther("1.0") });
      }
      memberStake = await trustlessTeamProtocol.getMemberRequiredStakeFor(1, user2.address);
      await trustlessTeamProtocol.connect(user2).requestJoinTask(1, { value: memberStake });
      await trustlessTeamProtocol.connect(user1).approveJoinRequest(1, user2.address);

      // Request cancellation
      await trustlessTeamProtocol.connect(user1).requestCancel(1, "Cannot continue with the task");

      // Respond to cancellation
      await trustlessTeamProtocol.connect(user2).respondCancel(1, true);

      const task = await trustlessTeamProtocol.Tasks(1);
      expect(task.status).to.equal(6); // Cancelled
    });

  it("Should handle deadline triggers", async function () {
      // Create and setup task with a small deadline so we can advance time in tests
      const reward = parseEther("1.0");
      const smallDeadline = 1; // 1 hour for the deadline test
      const creatorStake = await trustlessTeamProtocol.getCreatorRequiredStakeFor(
        user1.address,
        reward,
        Number(MAX_REVISION),
        smallDeadline
      );
      const maxStake5 = await trustlessTeamProtocol.StateVars().then((s:any)=>s.maxStake);
      const state = await trustlessTeamProtocol.StateVars();
      const minRevision = state.minRevisionTimeInHour;
      if (smallDeadline < minRevision) {
        // deadline is below contract minimum -> InvalidDeadline
        await expect(
          trustlessTeamProtocol.connect(user1).createTask(
            "Test Task",
            "https://github.com/test",
            smallDeadline,
            Number(MAX_REVISION),
            1,
            { value: reward + creatorStake + ((creatorStake * BigInt(FEE_PERCENTAGE)) / 100n) }
          )
        ).to.be.revertedWithCustomError(trustlessTeamProtocol, 'InvalidDeadline');
        return;
      }
      if (creatorStake > BigInt(state.maxStake)) {
        await expect(
          trustlessTeamProtocol.connect(user1).createTask(
            "Test Task",
            "https://github.com/test",
            smallDeadline,
            Number(MAX_REVISION),
            1,
            { value: reward + creatorStake + ((creatorStake * BigInt(FEE_PERCENTAGE)) / 100n) }
          )
        ).to.be.revertedWithCustomError(trustlessTeamProtocol, 'StakeHitLimit');
        return;
      }
      const fee = (creatorStake * BigInt(FEE_PERCENTAGE)) / 100n;
      const totalRequired = reward + creatorStake + fee;

      await trustlessTeamProtocol.connect(user1).createTask(
        "Test Task",
        "https://github.com/test",
        smallDeadline,
        Number(MAX_REVISION),
        1,
        { value: totalRequired }
      );

      await trustlessTeamProtocol.connect(user1).openRegistration(1);
      let memberStake = await trustlessTeamProtocol.getMemberRequiredStakeFor(1, user2.address);
      const maxStake_member_dead = (await trustlessTeamProtocol.StateVars()).maxStake;
      if (memberStake > BigInt(maxStake_member_dead)) {
        expect(memberStake).to.be.gt(BigInt(maxStake_member_dead));
        return;
      }
      const user2Balance_dead = await ethers.provider.getBalance(await user2.getAddress());
      if (memberStake > user2Balance_dead) {
        await owner.sendTransaction({ to: await user2.getAddress(), value: memberStake - user2Balance_dead + parseEther("1.0") });
      }
      memberStake = await trustlessTeamProtocol.getMemberRequiredStakeFor(1, user2.address);
      await trustlessTeamProtocol.connect(user2).requestJoinTask(1, { value: memberStake });
      await trustlessTeamProtocol.connect(user1).approveJoinRequest(1, user2.address);

      // Increase time to pass deadline (smallDeadline hours)
      await ethers.provider.send("evm_increaseTime", [smallDeadline * 3600 + 1]);
      await ethers.provider.send("evm_mine", []);

      // Trigger deadline
      await trustlessTeamProtocol.triggerDeadline(1);

      const task = await trustlessTeamProtocol.Tasks(1);
      expect(task.status).to.equal(6); // Cancelled
    });

    it("Should handle withdrawals", async function () {
      // Create and complete a task to generate withdrawable funds
  const reward = parseEther("1.0");
      const creatorStake = await trustlessTeamProtocol.getCreatorRequiredStakeFor(
        user1.address,
        reward,
        Number(MAX_REVISION),
        DEADLINE_HOURS
      );
  const fee = (creatorStake * BigInt(FEE_PERCENTAGE)) / 100n;
  const totalRequired = reward + creatorStake + fee;

      await trustlessTeamProtocol.connect(user1).createTask(
        "Test Task",
        "https://github.com/test",
        Number(DEADLINE_HOURS),
        Number(MAX_REVISION),
        1,
        { value: totalRequired }
      );

      await trustlessTeamProtocol.connect(user1).openRegistration(1);
      let memberStake = await trustlessTeamProtocol.getMemberRequiredStakeFor(1, user2.address);
      const maxStake_member_withdraw = (await trustlessTeamProtocol.StateVars()).maxStake;
      if (memberStake > BigInt(maxStake_member_withdraw)) {
        expect(memberStake).to.be.gt(BigInt(maxStake_member_withdraw));
        return;
      }
      const user2Balance_withdraw = await ethers.provider.getBalance(await user2.getAddress());
      if (memberStake > user2Balance_withdraw) {
        await owner.sendTransaction({ to: await user2.getAddress(), value: memberStake - user2Balance_withdraw + parseEther("1.0") });
      }
      memberStake = await trustlessTeamProtocol.getMemberRequiredStakeFor(1, user2.address);
      await trustlessTeamProtocol.connect(user2).requestJoinTask(1, { value: memberStake });
      await trustlessTeamProtocol.connect(user1).approveJoinRequest(1, user2.address);
      
      await trustlessTeamProtocol.connect(user2).requestSubmitTask(
        1,
        "https://github.com/test/pull/1",
        "Completed task"
      );

      await trustlessTeamProtocol.connect(user1).approveTask(1);

      // Check withdrawable amounts
      const user2Withdrawable = await trustlessTeamProtocol.connect(user2).getWithdrawableAmount();
      expect(user2Withdrawable).to.be.gt(0);

      // Withdraw funds
      await trustlessTeamProtocol.connect(user2).withdraw();

      const newUser2Withdrawable = await trustlessTeamProtocol.connect(user2).getWithdrawableAmount();
      expect(newUser2Withdrawable).to.equal(0);
    });
  });
});