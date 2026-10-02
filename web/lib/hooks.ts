"use client";

import {useQuery} from "@tanstack/react-query";
import {parseAbiItem} from "viem";
import {usePublicClient, useReadContract} from "wagmi";

import {useDeployment} from "./deployments";
import {standingAbi} from "./standingAbi";

/// Chain-aware on purpose: the same address holds different contracts on
/// different chains, so a module-level constant would read the faucet token as
/// Standing when the wallet is on Robinhood testnet.
export function useStandingContract() {
  const {standing, supported} = useDeployment();
  return {address: standing, abi: standingAbi, enabled: supported} as const;
}

const MANDATE_CREATED = parseAbiItem(
  "event MandateCreated(bytes32 indexed id, address indexed payer, address indexed merchant, address token, uint256 maxAmount, uint64 minInterval, uint64 expiresAt, uint32 epoch)",
);

export type MandateRow = {
  id: `0x${string}`;
  payer: `0x${string}`;
  merchant: `0x${string}`;
  token: `0x${string}`;
  maxAmount: bigint;
  minInterval: bigint;
  /// 0 prepaid, 1 postpaid. Not in the event, so it comes from stored terms.
  chargeKind: number;
  /// 1 active, 2 revoked.
  status: number;
  chargeCount: number;
};

/// There is no onchain index of a payer's or merchant's mandates, because
/// maintaining one would cost gas on every charge to serve a list the client
/// can assemble itself. So the list comes from logs.
export function useMandates(role: "payer" | "merchant", who: `0x${string}` | undefined) {
  const client = usePublicClient();
  const {address: standing, enabled} = useStandingContract();
  const {deployedAt} = useDeployment();

  return useQuery({
    queryKey: ["mandates", role, who, standing, deployedAt.toString()],
    enabled: Boolean(client && who && enabled),
    queryFn: async (): Promise<MandateRow[]> => {
      if (!client || !who) return [];

      const logs = await client.getLogs({
        address: standing,
        event: MANDATE_CREATED,
        args: role === "payer" ? {payer: who} : {merchant: who},
        fromBlock: deployedAt,
        toBlock: "latest",
      });

      if (logs.length === 0) return [];

      // `chargeKind` is not in the event, and without it every row of a
      // merchant's list looks identical. Read the stored record instead, which
      // also gives live status and charge count rather than creation-time
      // values.
      const records = await client.multicall({
        contracts: logs.map((l) => ({
          address: standing,
          abi: standingAbi,
          functionName: "getMandate" as const,
          args: [l.args.id as `0x${string}`] as const,
        })),
        allowFailure: true,
      });

      return logs.map((l, i) => {
        const r = records[i];
        const rec =
          r?.status === "success"
            ? (r.result as unknown as {
                terms: {chargeKind: number};
                status: number;
                chargeCount: number;
              })
            : undefined;

        return {
          id: l.args.id as `0x${string}`,
          payer: l.args.payer as `0x${string}`,
          merchant: l.args.merchant as `0x${string}`,
          token: l.args.token as `0x${string}`,
          maxAmount: l.args.maxAmount as bigint,
          minInterval: l.args.minInterval as bigint,
          chargeKind: Number(rec?.terms?.chargeKind ?? 0),
          status: Number(rec?.status ?? 0),
          chargeCount: Number(rec?.chargeCount ?? 0),
        };
      });
    },
  });
}

export type HoldRow = {
  holdId: bigint;
  mandateId: `0x${string}`;
  payer: `0x${string}`;
  merchant: `0x${string}`;
  token: `0x${string}`;
  amount: bigint;
  unlockAt: bigint;
  status: number;
  feeBps: number;
};

/// Hold ids are sequential from 1, so the set is enumerable without an index:
/// read `nextHoldId` and walk back. Fine at demo scale, and the reason to
/// reach for a real indexer later.
export function useHolds(role: "payer" | "merchant", who: `0x${string}` | undefined) {
  const client = usePublicClient();
  const contract = useStandingContract();

  return useQuery({
    queryKey: ["holds", role, who, contract.address],
    enabled: Boolean(client && who && contract.enabled),
    refetchInterval: 8_000,
    queryFn: async (): Promise<HoldRow[]> => {
      if (!client || !who) return [];

      const next = (await client.readContract({
        address: contract.address,
        abi: contract.abi,
        functionName: "nextHoldId",
      })) as bigint;

      const ids: bigint[] = [];
      const first = next > 200n ? next - 200n : 1n;
      for (let i = next - 1n; i >= first && i >= 1n; i -= 1n) ids.push(i);
      if (ids.length === 0) return [];

      const results = await client.multicall({
        contracts: ids.map((holdId) => ({
          address: contract.address,
          abi: contract.abi,
          functionName: "getHold" as const,
          args: [holdId] as const,
        })),
        allowFailure: true,
      });

      const rows: HoldRow[] = [];
      results.forEach((r, i) => {
        if (r.status !== "success" || !r.result) return;
        const h = r.result as unknown as HoldRow;
        const match = role === "payer" ? h.payer : h.merchant;
        if (match?.toLowerCase() !== who.toLowerCase()) return;
        rows.push({...h, holdId: ids[i]});
      });
      return rows;
    },
  });
}

export function useStanding(payer: `0x${string}` | undefined) {
  const standingContract = useStandingContract();
  const enabled = Boolean(payer && standingContract.enabled);
  const args = payer ? ([payer] as const) : undefined;

  const standing = useReadContract({...standingContract, functionName: "standingOf", args, query: {enabled}});
  const ceiling = useReadContract({...standingContract, functionName: "reversalCeiling", args, query: {enabled}});
  const vested = useReadContract({...standingContract, functionName: "isVested", args, query: {enabled}});
  const untilVested = useReadContract({...standingContract, functionName: "cyclesUntilVested", args, query: {enabled}});
  const suspended = useReadContract({...standingContract, functionName: "isSuspended", args, query: {enabled}});
  const untilRestored = useReadContract({...standingContract, functionName: "cyclesUntilRestored", args, query: {enabled}});
  const inWindow = useReadContract({...standingContract, functionName: "reversalsInWindow", args, query: {enabled}});

  return {
    record: standing.data as
      | {
          cumulativeCleanSettled: bigint;
          cleanSettlements: number;
          reversals: number;
          distinctMerchantsReversed: number;
          restoreAtClean: number;
          recentOutcomes: number;
          recentCount: number;
        }
      | undefined,
    ceiling: ceiling.data as bigint | undefined,
    vested: vested.data as boolean | undefined,
    cyclesUntilVested: untilVested.data as number | undefined,
    suspended: suspended.data as boolean | undefined,
    cyclesUntilRestored: untilRestored.data as number | undefined,
    reversalsInWindow: inWindow.data as number | undefined,
    isLoading: standing.isLoading,
  };
}

export function useMerchantStanding(merchant: `0x${string}` | undefined) {
  const standingContract = useStandingContract();
  const enabled = Boolean(merchant && standingContract.enabled);
  const args = merchant ? ([merchant] as const) : undefined;

  const standing = useReadContract({
    ...standingContract,
    functionName: "merchantStandingOf",
    args,
    query: {enabled},
  });
  const window = useReadContract({...standingContract, functionName: "windowFor", args, query: {enabled}});
  const flagged = useReadContract({...standingContract, functionName: "isMerchantFlagged", args, query: {enabled}});
  const policy = useReadContract({...standingContract, functionName: "acceptancePolicyOf", args, query: {enabled}});

  return {
    record: standing.data as
      | {settlements: number; reversals: number; distinctPayersReversed: number}
      | undefined,
    window: window.data as bigint | undefined,
    flagged: flagged.data as boolean | undefined,
    policy: policy.data as
      | {set: boolean; refuseSuspended: boolean; maxReversalsInWindow: number; minCleanSettlements: number}
      | undefined,
  };
}
