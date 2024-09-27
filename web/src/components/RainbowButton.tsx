import SkyButton from "./SkyButton";
import { ConnectButton } from "@rainbow-me/rainbowkit";

const RainbowButton = () => {
  return (
    <SkyButton href="#" title="Button" className="px-2 py-0 mt-0 w-max">
      <ConnectButton
        label="Connect"
        accountStatus={{
          smallScreen: "avatar",
          largeScreen: "full",
        }}
      />
    </SkyButton>
  );
};

export default RainbowButton;
