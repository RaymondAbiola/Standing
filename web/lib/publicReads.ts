"use client";

import {useQuery} from "@tanstack/react-query";
import {createPublicClient, http} from "viem";

import {arbitrumSepolia, robinhoodTestnet} from "./chains";
import {DEPLOYMENTS} from "./deployments";
import {standingAbi} from "./standingAbi";

/*
 * Reads that need no wallet.
 *
 * Everything standing exposes is public, so the pages that matter most to a
 * stranger (a protocol summary, and looking up an address) should not sit
 * behind a connect button. The wagmi hooks are account-bound and report an
 * unsupported chain when nothing is connected, so these build their own
 * clients from the chain definitions instead.
 */
const CLIENTS = {
  [arbitrumSepolia.id]: createPublicClient({
    chain: arbitrumSepolia,
    transport: http(process.env.NEXT_PUBLIC_ARBITRUM_SEPOLIA_RPC),
  }),
  [robinhoodTestnet.id]: createPublicClient({chain: robinhoodTestnet, transport: http()}),
} as const;

export const PUBLIC_CHAINS = [arbitrumSepolia.id, robinhoodTestnet.id] as const;
export type PublicChainId = (typeof PUBLIC_CHAINS)[number];

export type ChainStats = {
  chainId: number;
  label: string;
  explorer: string;
  standing: `0x${string}`;
  charges: number;
  settled: number;
  reversed: number;
  held: number;
  inEscrow: bigint;
  settledValue: bigint;
  reversedValue: bigint;
};

/// Walks the hold ids and tallies outcomes.
///
/// Bounded at the most recent 300, which is plenty for a testnet deployment and
/// is the point past which this wants a real indexer rather than a longer loop.
const MAX_SCAN = 300n;

async function readChainStats(chainId: PublicChainId): Promise<ChainStats> {
  const client = CLIENTS[chainId];
  const d = DEPLOYMENTS[chainId];

  const next = (await client.readContract({
    address: d.standing,
    abi: standingAbi,
    functionName: "nextHoldId",
  })) as bigint;

  const total = next - 1n;
  const first = total > MAX_SCAN ? next - MAX_SCAN : 1n;

  const ids: bigint[] = [];
  for (let i = first; i < next; i += 1n) ids.push(i);

  let settled = 0;
  let reversed = 0;
  let held = 0;
  let inEscrow = 0n;
  let settledValue = 0n;
  let reversedValue = 0n;

  if (ids.length > 0) {
    const results = await client.multicall({
      contracts: ids.map((holdId) => ({
        address: d.standing,
        abi: standingAbi,
        functionName: "getHold" as const,
        args: [holdId] as const,
      })),
      allowFailure: true,
    });

    for (const r of results) {
      if (r.status !== "success" || !r.result) continue;
      const h = r.result as unknown as {amount: bigint; status: number};
      if (h.status === 1) {
        held += 1;
        inEscrow += h.amount;
      } else if (h.status === 2) {
        settled += 1;
        settledValue += h.amount;
      } else if (h.status === 3) {
        reversed += 1;
        reversedValue += h.amount;
      }
    }
  }

  return {
    chainId,
    label: d.label,
    explorer: d.explorer,
    standing: d.standing,
    charges: Number(total),
    settled,
    reversed,
    held,
    inEscrow,
    settledValue,
    reversedValue,
  };
}

export function useChainStats() {
  return useQuery({
    queryKey: ["chainStats"],
    refetchInterval: 20_000,
    queryFn: async () => Promise.all(PUBLIC_CHAINS.map(readChainStats)),
  });
}

export type AddressRecord = {
  chainId: number;
  label: string;
  explorer: string;
  payer: {
    cleanSettlements: number;
    reversals: number;
    distinctMerchantsReversed: number;
    cumulativeCleanSettled: bigint;
    ceiling: bigint;
    vested: boolean;
    cyclesUntilVested: number;
    suspended: boolean;
    cyclesUntilRestored: number;
    reversalsInWindow: number;
    sampleSize: number;
  };
  merchant: {
    settlements: number;
    reversals: number;
    distinctPayersReversed: number;
    window: bigint;
    flagged: boolean;
    policySet: boolean;
    minCleanSettlements: number;
    maxReversalsInWindow: number;
    refuseSuspended: boolean;
  };
};

/// Both sides of an address's record on one chain.
///
/// Every address is potentially both a payer and a merchant, and the contract
/// keeps separate books for each, so a lookup has to show both rather than ask
/// which one you meant.
async function readAddressRecord(
  chainId: PublicChainId,
  who: `0x${string}`,
): Promise<AddressRecord> {
  const client = CLIENTS[chainId];
  const d = DEPLOYMENTS[chainId];
  const base = {address: d.standing, abi: standingAbi} as const;

  const [
    standing,
    ceiling,
    vested,
    untilVested,
    suspended,
    untilRestored,
    inWindow,
    sample,
    merchant,
    window,
    flagged,
    policy,
  ] = await client.multicall({
    contracts: [
      {...base, functionName: "standingOf", args: [who]},
      {...base, functionName: "reversalCeiling", args: [who]},
      {...base, functionName: "isVested", args: [who]},
      {...base, functionName: "cyclesUntilVested", args: [who]},
      {...base, functionName: "isSuspended", args: [who]},
      {...base, functionName: "cyclesUntilRestored", args: [who]},
      {...base, functionName: "reversalsInWindow", args: [who]},
      {...base, functionName: "sampleSize", args: [who]},
      {...base, functionName: "merchantStandingOf", args: [who]},
      {...base, functionName: "windowFor", args: [who]},
      {...base, functionName: "isMerchantFlagged", args: [who]},
      {...base, functionName: "acceptancePolicyOf", args: [who]},
    ],
    allowFailure: true,
  });

  const s = standing.result as unknown as
    | {cumulativeCleanSettled: bigint; cleanSettlements: number; reversals: number; distinctMerchantsReversed: number}
    | undefined;
  const m = merchant.result as unknown as
    | {settlements: number; reversals: number; distinctPayersReversed: number}
    | undefined;
  const p = policy.result as unknown as
    | {set: boolean; refuseSuspended: boolean; maxReversalsInWindow: number; minCleanSettlements: number}
    | undefined;

  return {
    chainId,
    label: d.label,
    explorer: d.explorer,
    payer: {
      cleanSettlements: Number(s?.cleanSettlements ?? 0),
      reversals: Number(s?.reversals ?? 0),
      distinctMerchantsReversed: Number(s?.distinctMerchantsReversed ?? 0),
      cumulativeCleanSettled: (s?.cumulativeCleanSettled ?? 0n) as bigint,
      ceiling: (ceiling.result ?? 0n) as bigint,
      vested: Boolean(vested.result),
      cyclesUntilVested: Number(untilVested.result ?? 0),
      suspended: Boolean(suspended.result),
      cyclesUntilRestored: Number(untilRestored.result ?? 0),
      reversalsInWindow: Number(inWindow.result ?? 0),
      sampleSize: Number(sample.result ?? 0),
    },
    merchant: {
      settlements: Number(m?.settlements ?? 0),
      reversals: Number(m?.reversals ?? 0),
      distinctPayersReversed: Number(m?.distinctPayersReversed ?? 0),
      window: (window.result ?? 0n) as bigint,
      flagged: Boolean(flagged.result),
      policySet: Boolean(p?.set),
      minCleanSettlements: Number(p?.minCleanSettlements ?? 0),
      maxReversalsInWindow: Number(p?.maxReversalsInWindow ?? 0),
      refuseSuspended: Boolean(p?.refuseSuspended),
    },
  };
}

export function useAddressRecord(who: string | undefined) {
  const valid = typeof who === "string" && /^0x[0-9a-fA-F]{40}$/.test(who);

  return useQuery({
    queryKey: ["addressRecord", who],
    enabled: valid,
    queryFn: async () =>
      Promise.all(PUBLIC_CHAINS.map((c) => readAddressRecord(c, who as `0x${string}`))),
  });
}
