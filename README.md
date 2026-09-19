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

| Network | Chain ID | Role | Standing |
|---|---|---|---|
| Arbitrum Sepolia | 421614 | Primary. Demo deployment judges can click through | [`0x3d30b84664e33ce51015a6b310544f45d63aa5d3`](https://sepolia.arbiscan.io/address/0x3d30b84664e33ce51015a6b310544f45d63aa5d3) |
| Robinhood Chain | 4663 | Mainnet, under a hard exposure cap | not yet deployed |
| Robinhood Chain testnet | 46630 | Integration testing | not yet deployed |

Permit2 sits at `0x000000000022D473030F116dDEE9F6B43aC78BA3` on all three, with
identical bytecode.

The Robinhood Chain public RPC is rate limited and not meant for production load.

### Deploying

```
forge script script/Deploy.s.sol --rpc-url arbitrum_sepolia \
  --private-key $PRIVATE_KEY --broadcast --verify -vvv
```

The script asserts the Permit2 address holds code before deploying, since
pointing at an empty address would produce a contract that reverts on every
charge.

## Status

Buildathon work in progress. Contracts are unaudited.

A charge pulls through Permit2 and books the funds into escrow behind an unlock time. Anyone can
call `finalize` once the window closes, which pays the merchant.

The payer can `reverse` a hold inside its window and get the funds back.

**Reversal is unconditional right now, which is not shippable.** A reversal right that costs nothing
is a free option no merchant would accept. The right has to vest through clean payment history and
be capped by the value that history represents. That gate lands with the standing book.

The deployed Arbitrum Sepolia address above predates escrow and pays merchants directly. It will be
redeployed.
