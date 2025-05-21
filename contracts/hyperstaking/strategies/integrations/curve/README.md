Based on Vyper official implementation:
- https://github.com/curvefi/curve-core             (pool & router ABIs)
- https://docs.curve.finance/router/CurveRouterNG   (calldata layout)

Notes:
- Minimal ABI subset for one-hop swaps `ICurvePoolMinimal`, `ICurveRouterMinimal`.
- Hardhat-friendly mock (`MockCurveRouter.sol`) moves real ERC-20s at a fixed rate.
- Uses OpenZeppelin 5.x imports and relative paths.
