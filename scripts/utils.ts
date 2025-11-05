import { run } from "hardhat";

export async function verify(address: string, constructorArguments: any[] = []) {
  try {
    await run("verify:verify", {
      address,
      constructorArguments,
    });
    console.log("Contract at", address, "verified!");
  } catch (err: any) {
    if (err.message.toLowerCase().includes("already verified")) {
      console.log("Contract at", address, "is already verified!");
    } else {
      console.error("Error verifying contract at", address, ":", err);
    }
  }
}