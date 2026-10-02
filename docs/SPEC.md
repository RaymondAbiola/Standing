# Standing

**Standing orders for stablecoins, with recourse.**

Recurring stablecoin payments that a merchant can pull on a schedule, held in escrow through a reversal window, gated by reputation the payer earns through clean payment history.

Built for Arbitrum Open House Singapore. Buildathon window: September 14 to October 4, 2026.

---

## 1. The problem

**Chains can only push. Subscriptions require pull.**

Every subscription on earth works on a pull model: the payer authorizes once, and the payee draws funds repeatedly. Blockchains are architecturally push-only, because only the holder of a private key can move funds. There is no way to express "charge me $10 every month" with stablecoins without handing over custody.

Two consequences, both independently documented:

**No standard exists.** Every platform solves the same three problems differently: how the payer pre-authorizes, how the schedule is enforced, and how failed charges are retried. The absence of a standard is a large part of why adoption has lagged the pitch decks.

**No recourse exists.** If a payer pre-authorized a pull, they have no enforcement mechanism beyond taking the merchant to court. US chargeback volume is projected at 146 million disputes worth $15.3 billion in 2026. Stablecoins serve none of it.

---

## 2. The solution

Three parts.

**The mandate.** A permission slip signed once and registered onchain. It states who may charge, how much at most, how often at most, and it carries a revoke button that only the payer controls and that works immediately without the merchant's cooperation.

**The window.** A charge does not go to the merchant. It goes into escrow with an unlock time. During the window the payer can reverse it. After the window it finalizes automatically. No arbiter, no adjudication, no trusted third party.

**Standing.** The right to reverse is earned, not granted. It vests with clean payment history and it is capped by the value that history represents. This is what makes the window safe to offer.

```
Today:      payer ──$10──> merchant                  (irreversible)

Standing:   payer ──$10──> [escrow, unlockAt] ──> merchant
                                  │
                             payer reverses
                             (if right is vested
                              and within ceiling)
                                  │
                                  └──> payer
```

---

## 3. Why it has to be onchain

The mandate terms, the revoke button and the escrow must live somewhere neither party controls and neither party can edit. If the permission slip lived on the merchant's server they could change the cap, ignore the revocation, or deny it ever existed.

The stronger answer: **portable two-sided reputation.** A payer's chargeback history at Visa is visible only to their own issuer, because that data is the network's moat. Standing makes reversal history public and readable by any merchant before they accept a mandate. That is structurally impossible inside a card network and it is the part of this that cannot be replicated offchain.

---

## 4. Architecture

### Contracts

| Contract | Responsibility |
|---|---|
| `MandateRegistry` | Create, revoke, validate mandates. EIP-712 terms, per-payer nonce |
| `Escrow` | Per-charge holds with `unlockAt`. Finalize, reverse, fee collection |
| `StandingBook` | Payer reputation state. Vesting, ceiling, suspension, dispersion |
| `MerchantRegistry` | Merchant history, window length, acceptance policy |

### Token permission: Permit2 AllowanceTransfer

The payer grants a Permit2 allowance scoped to an amount and an expiry. The merchant calls `charge(mandateId)`, the contract validates cadence and cap, then pulls via Permit2 into escrow.

Permit2 closes the obvious objection. Without it you are asking a treasury for an open-ended ERC-20 approval, which security-conscious businesses refuse. Permit2 gives amount-scoped, expiring permissions a spender can draw down repeatedly, which is exactly recurring-pull semantics.

The payer ends up with two independent kill switches: revoke the mandate in the registry, or let the Permit2 expiry lapse.

### Signature validation: ECDSA plus EIP-1271

A large share of target payers hold funds in a Safe. Without EIP-1271, Safes cannot sign mandates and most of the market is excluded. This lands in the first four commits, not as an afterthought.

### Rejected alternatives

**ERC-4337 session keys.** The trust model is wrong. A session key says "this party acts as me," but the merchant is not acting as the payer, it is pulling from the payer. Different relationship, different failure modes. It also requires the payer to already run a 4337 account and drags in bundlers, paymasters and EntryPoint for no gain, while pushing escrow and standing logic out of the path where they need to sit.

**ERC-7579 module.** The correct long-term architecture, and on the roadmap. Wrong for v1 because it requires the payer to run a compatible smart account, which means customer acquisition includes a wallet migration. Nobody switches treasury wallets to trial a billing vendor.

**Standalone allowance contract wins on one property that outweighs every architectural nicety: it works with whatever wallet the payer already has.**

---

## 5. Mechanism design

### Reversal rights vest

A mandate from an address with no history gets no reversal right on its first charges. The right activates after N clean cycles.

This is the primary Sybil defense. A fresh address cannot reverse anything, so it has nothing to steal. To unlock a reversal right the attacker must pay honestly first, which leaves the merchant net positive on every attacker who tries.

### The ceiling is value-based, not binary

Reversal ceiling is a function of `cumulativeCleanSettled`, not cycle count. Settle $30 cleanly and you can reverse up to roughly $10. Settle $50,000 cleanly and your ceiling is far higher.

This closes reputation laundering: vesting cheaply on a $1 per month service must not unlock the right to reverse a $500 enterprise plan. The size of the asset destroyed by fraud scales with the size of the theft enabled.

The scarce resource is **elapsed time with clean history**, which is the one thing a fresh address cannot buy at any price.

### Vesting is global, not per-merchant

Per-merchant vesting means you are never protected when you need protection, because your risky purchases are from merchants you have never used. Under per-merchant rules that is exactly when you hold zero rights, so the protection exists only where it was unnecessary. It also weakens Sybil resistance, since an identity worth something at only one merchant is cheap to churn.

### Rights never decay through non-use

A right that expires if unused creates a use-it-or-lose-it incentive, which pays people to file frivolous reversals to keep the right alive. That single argument settles it. A payer who never reverses is the best kind of payer and must not be penalized for it.

### Abuse suspends and is re-earned

A reversal is not evidence of abuse. Legitimate reversals are the product. So the trigger is a **rate** over a rolling window with a minimum sample size, and tripping it suspends the right until some number of clean cycles restore it. Self-healing and proportionate.

### Abuse is measured by dispersion, not count

A payer with five reversals all against one merchant and zero against twenty others is not a fraudster, they are telling you that merchant is broken. Reversals spread thinly across unrelated merchants indicate a payer problem. Reversals concentrated on one merchant indicate a merchant problem, and the penalty moves to the other side of the ledger.

Same data, two products: the abuse detector doubles as the merchant-fraud detector.

### A failed charge is not a reversal

If the payer's wallet is empty on the 1st, that is not a reversal and must never be scored as one. Conflating them poisons the reputation data. Default retry policy: retry daily for five days, then suspend the mandate with no penalty to the payer's standing.

### The merchant window shortens with history

A fixed hold on every charge is a real cashflow cost to merchants and the most likely reason they decline. A new merchant waits longer. One with a long clean record waits hours. This is the merchant-side mirror of payer standing and it is the piece competitors cannot copy quickly, because it is a mechanism rather than a feature.

---

## 6. Where reversal rights apply

| Charge type | Reversal | Why |
|---|---|---|
| Recurring, prepaid, ongoing relationship | Yes, once vested | Reversal is effectively a late cancellation, and service cutoff caps merchant loss at one cycle |
| Usage-based, billed after consumption | No, or merchant consent only | The merchant already delivered |
| One-off, no ongoing relationship | Out of scope for v1 | No cutoff leverage. Needs bonded adjudication, which only pencils out on large tickets |

Standing serves recurring prepaid billing. It is not a general dispute layer and should not claim to be.

---

## 7. Threat model

### The Sybil clawback

**Attack.** Create a fresh address, sign a mandate, consume one cycle, reverse, discard the address, repeat.

**Prize is bounded.** The merchant cuts off service the moment a reversal lands, so the attacker nets exactly one cycle per address. This is economically identical to free-trial abuse, which every SaaS company already prices into its margins.

**Vesting closes it.** A fresh address holds no reversal right. Unlocking one requires three clean settlements first, so the merchant is net positive on every attempt.

**Laundering is closed by the value ceiling.** Cheap history cannot unlock expensive theft.

### Supplementary signals

Address age and funding trail raise attacker cost. Funded Sybils trace somewhere. Treat these as score inputs, never as gates, because they are heuristic and gameable.

Optional business verification in exchange for a shorter window costs real customers nothing and destroys Sybil economics in the B2B segment. Worth having, not worth depending on. A design that only works because the customers happen to be well-behaved is not a design.

### Residual risk, stated plainly

This is not eliminated. Any permissionless system with free identities has a fraud floor. The achievable goal is narrower: make the attack unprofitable rather than impossible, and bound merchant loss per attempt to one capped cycle. Vesting does the first, service cutoff does the second.

### Aggregate reversal exposure

The ceiling caps a single reversal, not a payer's total. A payer vested with a
ceiling of C can reverse any number of separate holds worth up to C each, provided
every one is still inside its window.

What bounds that is the cadence floor the payer signed. The number of holds a
merchant can have open at once is roughly `window / minInterval`, so the worst
case a merchant is exposed to is:

```
aggregate exposure  =  ceiling  x  (window / minInterval)
```

| `minInterval` | Window | Holds open at once | Exposure at a 30.00 ceiling |
|---|---|---|---|
| 30 days | 5 days | 1 | 30.00 |
| 7 days | 5 days | 1 | 30.00 |
| 1 day | 5 days | 5 | 150.00 |
| 1 hour | 5 days | 120 | 3,600.00 |

For the case Standing is built for, a monthly subscription, the interval exceeds
the window and exactly one hold is ever open, so the ceiling means what it says.
The gap opens for high-frequency billing against a long window.

Two things blunt it and neither closes it. A merchant chooses whether to accept a
mandate at all, and `setAcceptancePolicy` lets it refuse payers it does not like,
so an absurd interval is a merchant's own decision. And reversals dispersed across
merchants suspend the right, though that does nothing for a single merchant being
drained.

**Not fixed in v1, and stated rather than hidden.** The proper fix is a rolling cap
on reversed value per unit time, alongside the per-reversal ceiling, so that
aggregate exposure stops scaling with hold count. That is a mechanism change, not a
parameter change, and it belongs after the buildathon.

The practical mitigation today is advice rather than code: a merchant should set
`minInterval` no shorter than its own hold window. At that point the two bounds
coincide and exposure is one hold.

### The single-merchant reverser

A payer who only ever reverses against one merchant never trips suspension, because
the dispersion condition deliberately ignores a single counterparty. Reversals
concentrated on one merchant are evidence about that merchant, and reading them as
payer abuse would punish the customers of a broken business.

The bound here is not onchain. The merchant withdraws service on the first reversal,
reversal history is public before a merchant accepts a mandate, and
`setAcceptancePolicy` declines the next one. Covered by
`test_singleMerchantRepeatReversalIsNotSuspendedOnchain`, which asserts the ceiling
stays frozen while this happens, since reversed value never counts as clean.

### What revokeAll does not do

`revokeAll` bumps the payer's epoch, which kills every outstanding mandate and stops
all future charges. It moves no money. Holds copy payer, merchant, token and amount
at charge time, and nothing in the reversal or settlement path reads the mandate
epoch, so funds already in escrow settle on the terms in force when they were taken.

That asymmetry is deliberate. A revocation that clawed back money already pulled
would let a payer take delivery and then empty escrow with one transaction, which is
the free option the whole standing mechanism exists to price. Covered by
`test_revokeMidWindowLeavesHoldIntact` and `test_revokeMidWindowStillAllowsReversal`:
a revoked mandate's open hold still settles, and the payer still keeps whatever
reversal right they had earned on it.

### Surfaces covered by tests

155 tests across eight suites, plus seven invariant properties holding over roughly
33,000 random call sequences. The suites worth naming:

- `Sybil.t.sol` measures what the churn-and-claw attack actually yields rather than
  asserting it reverts
- `StandingBook.t.sol` pins every threshold boundary, including that exactly 20
  percent is tolerated and 30 percent is not
- `Escrow.t.sol` closes the hold state machine in both directions, since every gap
  in it is a double spend
- The invariant suite asserts solvency, token conservation, and that standing never
  drifts from settlements

---

## 8. Parameters

All owner-settable within hard bounds so they can be tuned without redeployment.

| Parameter | Default | Purpose |
|---|---|---|
| Vesting threshold | 3 clean cycles | Before any reversal right activates |
| Reversal ceiling | `cumulativeCleanSettled / 3` | Caps theft against accumulated history |
| Abuse rate trigger | > 20% over trailing 10 cycles | Suspension threshold |
| Minimum sample | 5 cycles | Prevents small-sample false positives |
| Dispersion condition | 3 or more distinct merchants | Distinguishes payer abuse from merchant fraud |
| Suspension recovery | 3 clean cycles | Restores a suspended right |
| Window, new merchant | 5 days | Initial hold |
| Window, established merchant | Down to hours | Shortens with clean history |
| Retry policy | Daily for 5 days, then suspend mandate | Failed charge handling, no standing penalty |
| Protocol fee | Basis points, taken at finalize | Revenue |

---

## 9. Market and go-to-market

### Customer

Crypto-native businesses that bill on a monthly cycle. RPC and node providers, dev tooling, crypto SaaS, infrastructure vendors, DAOs paying recurring vendors.

Named targets: Alchemy, QuickNode, dRPC, Blockdaemon, Tenderly, and the long tail of smaller infra and tooling companies.

These buyers are enumerable, technical, engineering-led, reachable by DM, and fast to integrate. Revenue comes from customer number one, with no liquidity requirement and no network effects.

### Revenue

Basis points per settled charge. A merchant billing 500 customers at $30 monthly generates $15,000 of monthly volume, so the model works at small merchant counts.

### The wedge

Merchants who want stablecoin revenue today choose between begging customers to remember, holding customer funds themselves, or using a card processor and giving up the reasons they wanted stablecoins. Standing is the fourth option, and the reversal window is why their customers will agree to sign a mandate at all.

### Milestones

Written as commitments, because half the award releases against them.

- **Day 30:** contracts live on Robinhood Chain mainnet with exposure caps, one merchant integrated on testnet, survey and discovery findings published
- **Day 60:** two merchants charging real customers within caps, first reversal and first finalize observed in production
- **Day 90:** five merchants live, caps raised after external review, ERC-7579 module adapter shipped

### The main objection, and the answer

The escrow hold hurts merchant cashflow. The answer is the risk-scored window: a hold that shrinks as a merchant earns trust, and which for most merchants is already faster than the invoice-and-wait cycle they run today.

### Evidence plan

A survey measuring current billing behavior rather than hypothetical interest, plus 8 to 12 customer discovery conversations. Report the findings that hurt: if a meaningful share call the hold a dealbreaker, that goes in the submission next to the risk-scored window as the response.

---

## 10. Competitive landscape

Eco, Spark, Loop and Sablier all do recurring crypto billing. **None of them have a reversal window.**

Differentiation is the window plus portable two-sided standing, and the positioning is a neutral primitive rather than another billing SaaS. Streaming protocols solve a different problem: continuous flow, not "charge $29 on the 1st."

---

## 11. Why this chain

Reputation state is written on every settlement. That per-charge accounting is unaffordable on most chains, which is a large part of why nobody has built this.

On Robinhood Chain, with 100 millisecond blocks and negligible fees, per-charge state updates are not a cost consideration. "Reputation accounting on every transaction is only economic here" is a specific answer to why this belongs on this chain, rather than the generic one.

Robinhood Chain also reserves a minimum of one top-three slot in each Buildathon track for projects built on it.

---

## 12. Deployment

| Network | Role |
|---|---|
| Arbitrum Sepolia | Primary. Verified contracts, seeded demo merchant, the full flow judges click through |
| Robinhood Chain mainnet | Credibility. Same contracts, verified, hard per-mandate cap and documented total exposure limit |

Testnet deployment satisfies the qualification rule, which accepts Arbitrum Sepolia alongside Arbitrum One and Orbit chains.

**State the exposure cap out loud in the submission.** A stated limit reads as engineering judgment. Silence on it reads as recklessness, and unaudited contracts moving real customer money at two weeks old is a liability in the pitch, not an asset.

---

## 13. Judging alignment

| Criterion | How Standing answers it |
|---|---|
| Smart contract quality | Small surface, four contracts, invariant test suite, explicit threat model, stated exposure caps |
| Product-market fit | Enumerable B2B buyers, revenue from customer one, survey and discovery evidence |
| Innovation and creativity | Portable two-sided reversal reputation, which card networks structurally cannot offer |
| Real problem solving | Two independently documented gaps: no recurring standard, no recourse |
| Ecosystem alignment | Stablecoins and payments is a named focus area. Per-charge reputation is only economic on this chain |
| Long-term potential | Roadmap beyond the buildathon: 7579 adapter, raised caps after review, merchant fraud scoring as a second product |

---

## 14. Out of scope for v1

Stated deliberately, because scope honesty scores better than feature sprawl.

- One-off high-value escrow with bonded adjudication
- Usage-based billing with post-consumption reversal
- Fee-on-transfer and rebasing tokens
- Cross-chain mandates
- Zero-knowledge eligibility or private standing
- Fiat on and off ramps
- ERC-7579 module (roadmap, not v1)

---

## 15. Open questions

- Should the reversal ceiling divisor be a global parameter or per-merchant policy?
- Should merchants be able to opt out of reversals entirely in exchange for a longer window, and does that create a race to the bottom?
- Does a merchant's own standing need a separate abuse trigger, or does window length alone price it adequately?
- How should standing be handled when a payer rotates keys deliberately, for example a treasury migration, without opening a Sybil path?
