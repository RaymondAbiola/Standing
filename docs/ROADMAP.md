# Standing: build roadmap

36 commits across 16 days. Sequenced so a demo-able core exists by commit 17 and mainnet is live by commit 28.

## Foundation, day 1

1. `chore: init foundry project, CI, solhint, Arbitrum Sepolia + Robinhood Chain configs`
2. `feat: MandateTerms struct and EIP-712 typehashes`
3. `feat: signature validation with ECDSA and EIP-1271 for Safe payers`
4. `test: EIP-712 digest fixtures and 1271 mock signer`

## Core charge path, days 2 to 3

5. `feat: MandateRegistry create and revoke with per-payer nonce`
6. `test: mandate lifecycle, replay rejection, revoke is immediate`
7. `feat: cadence enforcement, minInterval and no early pulls`
8. `feat: cap enforcement, per-charge max and mandate expiry`
9. `feat: Permit2 AllowanceTransfer integration for pulls`
10. `test: charge path happy case plus every revert branch`
11. `chore: deploy v0 to Arbitrum Sepolia, verify, publish addresses`

## Escrow and the window, days 4 to 5

12. `feat: Escrow vault, per-charge hold with unlockAt`
13. `feat: permissionless finalize after window, pays merchant`
14. `feat: reverse by payer within window, returns funds`
15. `feat: protocol fee in bps, taken at finalize`
16. `test: escrow unit suite, no double finalize, no reverse post-window`
17. `test: invariant suite, escrow balance equals sum of open holds`

Commit 17 matters more than it looks. An invariant suite in the history is the cheapest credible signal of smart contract quality available, and that is an explicit judging criterion.

## Standing, days 6 to 8

18. `feat: StandingBook, per-payer counters and suspension state`
19. `feat: cumulativeCleanSettled accrues on finalize`
20. `feat: reversal ceiling as cumulativeCleanSettled / K`
21. `feat: vesting gate, no reversal right before N clean cycles`
22. `feat: dispersion tracking, distinct merchants reversed`
23. `feat: suspension on abuse trigger, re-earn after M clean cycles`
24. `test: standing state machine across full lifecycle`
25. `test: sybil scenario, fresh-address clawback yields zero`

Commit 25 is the most valuable commit message in the repo. A judge scrolling the log sees that the attack was considered and the answer encoded as a test.

## Merchant side, days 9 to 10

26. `feat: MerchantRegistry, window length derived from merchant history`
27. `feat: merchant acceptance policy, minimum payer standing`
28. `chore: deploy to Robinhood Chain mainnet with exposure caps, verified, params documented`
29. `chore: dual-network deploy scripts and address registry`
30. `feat: failed-charge retry policy, grace period then auto-revoke`
31. `test: window shortens as merchant accrues clean cycles`

Commit 30 carries the rule that a failed charge is never scored as a reversal. Conflating them poisons the reputation data.

## SDK and app, days 11 to 14

32. `feat: TypeScript SDK, createMandate link, charge, status webhook`
33. `feat: indexer for mandate and standing views`
34. `feat: merchant dashboard, mandates, charges, window, fees earned`
35. `feat: payer portal, view mandates, revoke, reverse`

## Pitch, days 15 to 16

36. `docs: threat model, sybil analysis, parameter rationale, 7579 roadmap`

## Running in parallel, not in the commit log

- Ship the survey by day 2 and let it collect for the full window
- 8 to 12 customer discovery conversations, starting day 1
- Both feed the go-to-market section, which carries half the award through milestone release
