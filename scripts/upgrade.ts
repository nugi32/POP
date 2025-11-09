import { ethers, upgrades } from "hardhat";
import { readFileSync } from "fs";
import { join } from "path";

export async function upgradeContract(contractName: string, proxyAddress: string) {
  console.log(`Upgrading ${contractName} at proxy ${proxyAddress}...`);

  const ContractFactory = await ethers.getContractFactory(contractName);
  const upgraded = await upgrades.upgradeProxy(proxyAddress, ContractFactory);
  await upgraded.waitForDeployment();
  const upgradedAddress = await upgraded.getAddress();

  console.log(`${contractName} upgraded at:`, upgradedAddress);
  return upgraded;
}

// If executed directly, read env or frontend addresses.json to find proxy address
async function main() {
  const contractName = process.env.CONTRACT_NAME || "TrustlessTeamProtocol";
  let proxyAddress = process.env.PROXY_ADDRESS;

  if (!proxyAddress) {
    // try reading frontend addresses file
    const addressesPath = join(__dirname, '..', 'frontend', 'src', 'contracts', 'addresses.json');
    try {
      const content = readFileSync(addressesPath, 'utf8');
      const addresses = JSON.parse(content);
      proxyAddress = addresses[contractName];
      if (!proxyAddress) {
        throw new Error(`No address found for ${contractName} in ${addressesPath}`);
      }
    } catch (err) {
      throw new Error(`Please set PROXY_ADDRESS or ensure ${addressesPath} exists and contains the proxy address. (${err})`);
    }
  }

  await upgradeContract(contractName, proxyAddress);
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}