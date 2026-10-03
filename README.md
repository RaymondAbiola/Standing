# Standing

**Standing orders for stablecoins, with recourse.**

Live app: **https://standing-xi.vercel.app**

> **If MetaMask warns you about this URL, that is a false positive on the host, not
> this app.** Blockaid, the service behind MetaMask's security alerts, flags
> `*.vercel.app` broadly because phishing kits are hosted there in volume. The
> warning fires on wallet connection, before this site has requested anything, and
> Rabby connects to the same URL with no warning at all. It has been reported to
> Blockaid as a false positive.
>
> The part that cannot be faked is onchain: both contracts are verified at the
> addresses in the table below, and the only approval this app ever requests is a
> bounded one (100,000 dUSDC to Permit2, see `web/components/Authorise.tsx`), never
> an unlimited allowance. You can also read any address's full record on the site
> without connecting a wallet at all.

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

| Network | Chain ID | Standing | Faucet token |
|---|---|---|---|
| Arbitrum Sepolia | 421614 | [`0xC91F8976…DCD7`](https://sepolia.arbiscan.io/address/0xC91F89766f5B0A8a2918f7C672eAf41B90FBDCD7) | [`0x9b14830d…Fdf5`](https://sepolia.arbiscan.io/address/0x9b14830dceb7f15f0Def9a25664C313a5C88Fdf5) |
| Robinhood Chain Testnet | 46630 | [`0x5719cd77…d4E7`](https://explorer.testnet.chain.robinhood.com/address/0x5719cd77c190420Ec38DC6dbea6Fc19D529Ad4E7) | [`0xDC37130a…4b8a`](https://explorer.testnet.chain.robinhood.com/address/0xDC37130a3f2D07EAacf6d8d66352932c79474b8a) |

Both are verified. Permit2 sits at `0x000000000022D473030F116dDEE9F6B43aC78BA3` on both, with
identical bytecode.

**Addresses are per chain and must never be collapsed into one value.** CREATE derives an address from
the deployer and its nonce, and the same deployer was used on both chains with independent nonce
sequences. An earlier deployment had Standing on Arbitrum Sepolia sharing an address with the faucet
token on Robinhood testnet, which would have made a single "the Standing contract" address read one as
the other. The four above happen not to collide, but the hazard is structural, so the frontend keys
addresses by chain id in `web/lib/deployments.ts`.

The faucet token is testnet scaffolding with an open mint, so the demo has something to charge in. It
is deployed from `script/` and nothing in `src/` imports it.

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

**The window is priced, not fixed.** A merchant nobody has transacted with waits 5 days; one with a
thousand clean settlements waits 2 hours. A merchant whose charges keep getting reversed stays at the
maximum however much volume it has. A fixed hold is the most likely reason a merchant declines this
outright, so it is something to be earned down rather than a flat cost.

The payer can `reverse` a hold inside its window, and the right to do so is earned rather than
granted. Three conditions gate it:

- **Vesting.** Three clean settlements before the right exists at all. A fresh address holds none,
  which is what stops a first reversal from being free.
- **A value ceiling.** At most a third of what the payer has settled cleanly, so cheap history
  cannot unlock an expensive reversal.
- **Suspension.** A reversal rate above 20% over the last 10 outcomes, spread across three or more
  distinct merchants, suspends the right until three more clean settlements restore it. Reversals
  concentrated on one merchant never trip it, because that pattern is evidence about the merchant.

`reversalBlocker(holdId, caller)` reports which condition is in the way, and the guard reads the same
predicate, so the frontend cannot offer a reversal the transaction would refuse.

### What standing deliberately does not catch

A payer who only ever reverses against one merchant never trips suspension, because the dispersion
rule that would catch it is the same rule protecting the customers of a broken merchant. It cannot be
one-sided.

The merchant's remedy is to decline the next mandate. `setAcceptancePolicy` lets a merchant require a
minimum number of clean settlements, cap recent reversals, and refuse suspended payers. Reversal
history is public, so a merchant reads it before agreeing to serve rather than discovering it after.

The web app in `web/` is the demo surface: a home page explaining the mechanism, a payer portal, and
a merchant dashboard. Run it with `cd web && bun install && bun run dev`.
