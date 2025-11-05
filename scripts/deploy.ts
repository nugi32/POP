import { ethers, upgrades } from "hardhat";
import { verify } from "./utils";
import { writeFileSync } from "fs";
import { join } from "path";

async function main() {
  // Deploy System Wallet first
  console.log("Deploying System Wallet...");
  const SystemWallet = await ethers.getContractFactory("System_wallet");
  const systemWallet = await upgrades.deployProxy(SystemWallet, [], {
    initializer: "initialize",
    kind: "uups"
  });
  await systemWallet.waitForDeployment();
  const systemWalletAddress = await systemWallet.getAddress();
  console.log("System Wallet deployed to:", systemWalletAddress);

  // Deploy EmployeeAssignment
  console.log("Deploying EmployeeAssignment...");
  const EmployeeAssignment = await ethers.getContractFactory("EmployeeAssignment");
  const employeeAssignment = await upgrades.deployProxy(EmployeeAssignment, [], {
    initializer: "initialize",
    kind: "uups"
  });
  await employeeAssignment.waitForDeployment();
  const employeeAssignmentAddress = await employeeAssignment.getAddress();
  console.log("EmployeeAssignment deployed to:", employeeAssignmentAddress);

  // Deploy UserRegister with required dependencies
  console.log("Deploying UserRegister...");
  const UserRegister = await ethers.getContractFactory("UserRegister");
  const userRegister = await upgrades.deployProxy(UserRegister, [
    employeeAssignmentAddress,
    systemWalletAddress
  ], {
    initializer: "initialize",
    kind: "uups"
  });
  await userRegister.waitForDeployment();
  const userRegisterAddress = await userRegister.getAddress();
  console.log("UserRegister deployed to:", userRegisterAddress);

  // Deploy Reputation System
  console.log("Deploying UserReputation...");
  const UserReputation = await ethers.getContractFactory("UserReputation");
  const reputation = await upgrades.deployProxy(UserReputation, [userRegisterAddress], {
    initializer: "__UserReputation_init",
    kind: "uups"
  });
  await reputation.waitForDeployment();
  const reputationAddress = await reputation.getAddress();
  console.log("Reputation System deployed to:", reputationAddress);

  // Wait for some blocks for verification
  console.log("Waiting for block confirmations...");
  await new Promise(resolve => setTimeout(resolve, 60000)); // Wait 60 seconds

  // Verify contracts on Etherscan
  console.log("\nVerifying contracts...");
  try {
    await verify(systemWalletAddress);
    await verify(employeeAssignmentAddress);
    await verify(userRegisterAddress);
    await verify(reputationAddress);
  } catch (error) {
    console.log("Error verifying contracts:", error);
  }

  // Save the deployed addresses
  const addresses = {
    SystemWallet: systemWalletAddress,
    EmployeeAssignment: employeeAssignmentAddress,
    UserRegister: userRegisterAddress,
    UserReputation: reputationAddress,
  };

  // Save addresses to a file
  const addressesPath = join(__dirname, '..', 'frontend', 'src', 'contracts', 'addresses.json');
  writeFileSync(
    addressesPath,
    JSON.stringify(addresses, null, 2)
  );

  console.log("\nDeployment completed! Addresses saved to frontend/src/contracts/addresses.json");
  
  return addresses;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });