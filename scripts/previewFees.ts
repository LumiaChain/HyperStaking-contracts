import { ZeroAddress } from "ethers";
import { ethers } from "hardhat";

async function main() {
  const provider = ethers.provider;

  const block = await provider.getBlock("latest");
  if (!block) {
    throw new Error("Failed to fetch the latest block");
  }
  if (!block.baseFeePerGas) {
    throw new Error("Node doesn’t support baseFeePerGas");
  }
  const baseFee = block.baseFeePerGas;

  const feeData = await provider.getFeeData();
  const maxFeePerGas = feeData.maxFeePerGas;
  const maxPriorityFeePerGas = feeData.maxPriorityFeePerGas;

  // baseFee and recommended fees in both wei and Gwei
  console.log("baseFee (wei):", baseFee.toString());
  console.log("baseFee (gwei):", ethers.formatUnits(baseFee, "gwei"));

  if (!maxFeePerGas || !maxPriorityFeePerGas) {
    console.warn(
      "Warning: maxFeePerGas or maxPriorityFeePerGas is not available.",
      "This may indicate the node does not support EIP-1559.",
    );
  } else {
    console.log("maxFeePerGas (wei):", maxFeePerGas.toString());
    console.log("maxFeePerGas (gwei):", ethers.formatUnits(maxFeePerGas, "gwei"));
    console.log("maxPriorityFeePerGas (wei):", maxPriorityFeePerGas.toString());
    console.log("maxPriorityFeePerGas (gwei):", ethers.formatUnits(maxPriorityFeePerGas, "gwei"));
  }

  // Estimate gas for a simple 0.01 ETH transfer
  const estimateGas = await provider.estimateGas({
    to: ZeroAddress,
    value: ethers.parseEther("0.01"),
  });
  console.log(
    "Estimated gas units for 0.01 ETH transfer:",
    estimateGas.toString(),
  );

  // Compute an approximate total fee = gasUnits × (baseFee + tip)
  // Use the recommended priority tip if available, otherwise 0
  const tip = maxPriorityFeePerGas ?? 0n;
  const totalFeePerUnit = baseFee + tip;
  const estimatedCost = estimateGas * totalFeePerUnit;

  console.log("Estimated total fee (wei):", estimatedCost.toString());
  console.log(
    "Estimated total fee (ETH):",
    ethers.formatEther(estimatedCost),
  );
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
