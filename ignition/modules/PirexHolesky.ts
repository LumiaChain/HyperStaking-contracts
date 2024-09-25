import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const PIREX_ETH_HOLESKY = "0x5F3aA7609768D3A0bAC351fa32E9909d1369D43a";
const PX_ETH_HOLESKY = "0x3E2D9E1a3743A4bD0A0cd7C7bf94Dd72bD431A7e";
const AUTO_PX_ETH_HOLESKY = "0x0e4bf0D7e9198756B821446C6Fb7A17Dfbfca198";
const UPX_ETH_HOLESKY = "0x3D87d61a88Ec8Fe57f5795C7abB5514e122b4014";

const PirexHoleskyModule = buildModule("PirexHoleskuModule", (m) => {
  const pirexEth = m.contractAt("PirexEth", PIREX_ETH_HOLESKY);
  const pxEth = m.contractAt("PxEth", PX_ETH_HOLESKY);
  const autoPxEth = m.contractAt("AutoPxEth", AUTO_PX_ETH_HOLESKY);
  const upxEth = m.contractAt("UpxEth", UPX_ETH_HOLESKY);

  return { pirexEth, pxEth, autoPxEth, upxEth };
});

export default PirexHoleskyModule;
