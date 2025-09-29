## HyperStaking (High-Level Overview)

HyperStaking is a modular, cross-chain staking framework built on the **Diamond Proxy (ERC-2535)** standard.  
It enables multi-pool staking with flexible asset support (native coins, ERC-20) and can be extended to  
real-world assets (RWAs) such as tokenized real estate, treasuries, or commodities. All staking and yield  
operations across many EVM chains are ultimately settled on the **Lumia Chain**, which acts as the hub.

**Core Mechanics:**

* Users stake tokens (ETH, stablecoins, etc.) on origin chains.  
* **Hyperlane** relays stake and redemption events to the Lumia Chain, where **ERC-4626 vault shares**  
  are minted to represent deposits plus accrued yield.  
* Strategies (e.g., Dinero, Curve, Superform) generate yield and report back, which automatically 
  updates the **price per share** of ERC-4626 vault tokens.  
* Both synchronous and asynchronous flows are supported, enabling instant exits or delayed redemption  
  requests with buffers for liquidity management.  

**Integrations:**

* **Dinero Protocol**: yield via Pirex/pxETH/apxETH.  
* **Superform**: USDC -> SuperUSDC strategy (ERC-4626/1155 flows).  
* **Gauntlet (Aera)**: USDC strategy via Aera multi-depositor vaults (gtUSDa).  
* **Curve**: swaps between stablecoins (e.g., USDT -> USDC) combined with Superform.  
* **Hyperlane**: secure cross-chain messaging for stake synchronization and redemption flow.  

**Extendability:**

* Flexible **Strategies interface** allows plugging in and supporting many types of investments,  
  both crypto-native and RWA, in synchronous or asynchronous mode.  
* New strategies can be added as independent modules without redeploying the core.  
* Any ERC-20 or native asset can be supported; NFTs can be wrapped.  
* The same vault/share model ensures a unified user experience, regardless of asset type.  
* Governance/ACL allows controlled upgrades without interrupting users, with potential for DAO-based management.  
