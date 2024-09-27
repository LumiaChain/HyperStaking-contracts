import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import {
  holesky,
  mainnet,
  optimism,
  polygon,
  base,
} from "wagmi/chains";

export const config = getDefaultConfig({
  appName: "hyperstaking-testweb",
  projectId: "YOUR_PROJECT_ID", // TODO
  chains: [
    mainnet,
    optimism,
    polygon,
    base,
    ...(process.env.NEXT_PUBLIC_ENABLE_TESTNETS === "true" ? [holesky] : []),
  ],
  ssr: true,
});
