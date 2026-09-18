# Standing

**Standing orders for stablecoins, with recourse.**

Blockchains can only push. Every subscription runs on pull, where the payer authorizes once and the
payee draws funds repeatedly. That mismatch is why crypto has no subscriptions without a merchant
taking custody, and why a payer who pre-authorized a pull has no remedy short of court.

Standing is an onchain mandate the payer signs once, stating who may charge, how much at most, and how
often. The revoke button belongs to the payer alone and works immediately. Each charge lands in escrow
with an unlock time rather than going straight to the merchant, and during that window the payer can
reverse it. After the window it finalizes on its own, with no arbiter and nobody to trust.

The right to reverse is earned, not granted. It vests only after clean payment history, and its ceiling
scales with the value that history represents, so cheap history cannot unlock expensive theft. A fresh
address holds no reversal right at all.

Full design in [docs/SPEC.md](docs/SPEC.md). Build sequence in [docs/ROADMAP.md](docs/ROADMAP.md).

## Layout

```
src/        contracts
test/       forge tests
script/     deploy and admin scripts
design/     brand assets
docs/       spec, roadmap, research
```

`sdk/` and `web/` arrive later as sibling folders.

## Quickstart

```
forge install
forge build
forge test
```

Copy `.env.example` to `.env` and fill it before running anything against a network.

## Networks

| Network | Chain ID | Role |
|---|---|---|
| Arbitrum Sepolia | 421614 | Primary. Demo deployment judges can click through |
| Robinhood Chain | 4663 | Mainnet, deployed under a hard exposure cap |
| Robinhood Chain testnet | 46630 | Integration testing |

The Robinhood Chain public RPC is rate limited and not meant for production load.

## Status

Buildathon work in progress. Contracts are unaudited. Mainnet deployments carry a documented
per-mandate cap and total exposure limit, stated in the deploy script.
