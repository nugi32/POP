import { ethers, upgrades } from "hardhat";

export async function upgradeContract(
  contractName: string,
  proxyAddress: string
) {
  console.log(`Upgrading ${contractName}...`);

  const ContractFactory = await ethers.getContractFactory(contractName);
  const upgraded = await upgrades.upgradeProxy(proxyAddress, ContractFactory);
  await upgraded.waitForDeployment();
  const upgradedAddress = await upgraded.getAddress();

  console.log(`${contractName} upgraded at:`, upgradedAddress);
  return upgraded;
}

// Usage example:
async function main() {
  // Get the proxy address from deployment or configuration
  const proxyAddress = process.env.PROXY_ADDRESS;
  
  if (!proxyAddress) {
    throw new Error("Please set PROXY_ADDRESS in your environment variables");
  }

  // Upgrade the contract
  const contractName = process.env.CONTRACT_NAME || "UserRegister"; // Default to UserRegister
  const upgraded = await upgradeContract(contractName, proxyAddress);
  console.log("Upgrade completed successfully!");
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}