import { TransactionResponse } from "ethers";

class TxCostTracker {
  private transactionCosts: bigint;

  constructor() {
    this.transactionCosts = 0n;
  }

  async includeTx(tx: TransactionResponse): Promise<void> {
    const receipt = await tx.wait();
    if (receipt && tx.gasPrice) {
      this.transactionCosts += receipt.cumulativeGasUsed * tx.gasPrice;
    }
  }

  getTotalCosts(): bigint {
    return this.transactionCosts;
  }
}

export default TxCostTracker;
