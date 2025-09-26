// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.27;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title LumiaGtUSDa
/// @notice ERC20 derived token that represents a staked position,
///         1:1 to Gauntlet USD Alpha (gtUSDa)
/// @dev Minted and burned only by the GauntletStrategy contract
contract LumiaGtUSDa is ERC20Burnable {
    /// @notice Address of the GauntletStrategy authorized to mint/burn
    address public immutable GAUNTLET_STRATEGY;

    /// @notice Error for unauthorized calls
    error NotGauntletStrategy();

    /// @dev Restricts calls to the GauntletStrategy
    modifier onlyGauntletStrategy() {
        if (msg.sender != GAUNTLET_STRATEGY) revert NotGauntletStrategy();
        _;
    }

    constructor() ERC20("Lumia gtUSDa", "l-gtUSDa") {
        GAUNTLET_STRATEGY = msg.sender; // strategy deploys this token
    }

    /// @notice Mint tokens, only callable by GauntletStrategy
    function mint(address to, uint256 amount) external onlyGauntletStrategy {
        _mint(to, amount);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}


