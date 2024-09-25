import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther, keccak256, toUtf8Bytes } from "ethers";

const PIREX_ETH_HOLESKY = "0x5F3aA7609768D3A0bAC351fa32E9909d1369D43a";
const PX_ETH_HOLESKY = "0x3E2D9E1a3743A4bD0A0cd7C7bf94Dd72bD431A7e";
const AUTO_PX_ETH_HOLESKY = "0x0e4bf0D7e9198756B821446C6Fb7A17Dfbfca198";
const UPX_ETH_HOLESKY = "0x3D87d61a88Ec8Fe57f5795C7abB5514e122b4014";

const MINTER_ROLE = keccak256(toUtf8Bytes("MINTER_ROLE"));
const BURNER_ROLE = keccak256(toUtf8Bytes("BURNER_ROLE"));
const GOVERNANCE_ROLE = keccak256(toUtf8Bytes("GOVERNANCE_ROLE"));

const INITIAL_DELAY = 0;
const DEPOSIT_SIZE = parseEther("32");
const PRE_DEPOSIT_SIZE = parseEther("1");
const MAX_ETH_BUFFER_SIZE = 1_000_000; // 100%

enum ContractType {
  PxEth,
  UpxEth,
  AutoPxEth,
  OracleAdapter,
  PirexEth,
  RewardRecipient
}

const PirexHoleskyModule = buildModule("PirexHoleskuModule", (m) => {
  const pirexEth = m.contractAt("PirexEth", PIREX_ETH_HOLESKY);
  const pxEth = m.contractAt("PxEth", PX_ETH_HOLESKY);
  const autoPxEth = m.contractAt("AutoPxEth", AUTO_PX_ETH_HOLESKY);
  const upxEth = m.contractAt("UpxEth", UPX_ETH_HOLESKY);

  return { pirexEth, pxEth, autoPxEth, upxEth };
});

const PirexMockModule = buildModule("PirexMockModule", (m) => {
  const admin = m.getAccount(0);
  const feesRecipient = m.getAccount(1);
  const rewardRecipient = m.getAccount(2);

  const BeaconChainDepositContract = m.contract("BeaconChainDepositMock");

  const pxEth = m.contract("PxEth", [admin, INITIAL_DELAY]);
  const upxEth = m.contract("UpxEth", [INITIAL_DELAY]);
  const pirexFees = m.contract("PirexFees", [feesRecipient]);

  const validatorQueue = m.library("ValidatorQueue");
  const pirexEth = m.contract("PirexEth", [
    pxEth,
    admin,
    BeaconChainDepositContract,
    upxEth,
    DEPOSIT_SIZE,
    PRE_DEPOSIT_SIZE,
    pirexFees,
    INITIAL_DELAY,
  ], {
    libraries: {
      ValidatorQueue: validatorQueue,
    },
  });

  m.call(pxEth, "grantRole", [MINTER_ROLE, pirexEth], { id: "grantRoleMinter" });
  m.call(pxEth, "grantRole", [BURNER_ROLE, pirexEth], { id: "grantRoleBurner" });

  const autoPxEth = m.contract("AutoPxEth", [pxEth, feesRecipient]);

  m.call(pirexEth, "grantRole", [GOVERNANCE_ROLE, admin]);
  m.call(pirexEth, "setContract", [ContractType.AutoPxEth, autoPxEth], { id: "setAutoPxEth" });
  m.call(pirexEth, "setContract", [ContractType.RewardRecipient, rewardRecipient], { id: "setRewardRecipient" });
  m.call(pirexEth, "setMaxBufferSizePct", [MAX_ETH_BUFFER_SIZE]);

  m.call(autoPxEth, "setPirexEth", [pirexEth]);

  return { pirexEth, pxEth, autoPxEth, upxEth };
});

export { PirexMockModule, PirexHoleskyModule };
