"use client";

import {useQueryClient} from "@tanstack/react-query";
import {useCallback, useEffect, useState} from "react";
import {usePublicClient, useWaitForTransactionReceipt, useWriteContract} from "wagmi";

/// Multiplier applied to the chain's current base fee.
///
/// MetaMask has been seen estimating `maxFeePerGas` at essentially the current
/// base fee with no headroom, which fails outright the moment the base fee
/// ticks up between estimating and submitting:
///
///   max fee per gas less than block base fee:
///   maxFeePerGas: 37316000 baseFee: 37788000
///
/// Arbitrum fees are small enough that the headroom costs nothing worth
/// measuring. A reversal at three times a 0.038 gwei base fee is a fraction of
/// a cent, and the alternative is a demo that fails on a fee race.
const FEE_HEADROOM = 3n;

type WriteArgs = Parameters<ReturnType<typeof useWriteContract>["writeContract"]>[0];

/// One write plus its receipt, with fee headroom and a refresh once it lands.
///
/// The invalidation matters as much as the fees. Without it the page waits on
/// the global poll interval, so a confirmed transaction leaves the UI unchanged
/// for several seconds and every step looks like it failed.
export function useTx() {
  const queryClient = useQueryClient();
  const publicClient = usePublicClient();
  const {writeContract: rawWrite, data: hash, isPending, error} = useWriteContract();
  const {isLoading, isSuccess} = useWaitForTransactionReceipt({hash});

  const [preparing, setPreparing] = useState(false);
  const [feeError, setFeeError] = useState<Error | null>(null);

  useEffect(() => {
    if (isSuccess) void queryClient.invalidateQueries();
  }, [isSuccess, hash, queryClient]);

  const writeContract = useCallback(
    (args: WriteArgs) => {
      setFeeError(null);

      // Fire and forget: callers invoke this straight from a click handler.
      void (async () => {
        setPreparing(true);
        try {
          const fees = await publicClient?.estimateFeesPerGas();
          if (fees?.maxFeePerGas) {
            rawWrite({
              ...args,
              maxFeePerGas: fees.maxFeePerGas * FEE_HEADROOM,
              maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
            } as WriteArgs);
            return;
          }
          // No fee data available: let the wallet decide rather than refuse.
          rawWrite(args);
        } catch (e) {
          setFeeError(e as Error);
          rawWrite(args);
        } finally {
          setPreparing(false);
        }
      })();
    },
    [publicClient, rawWrite],
  );

  return {
    writeContract,
    hash,
    error: error ?? feeError,
    busy: preparing || isPending || isLoading,
    confirmed: isSuccess,
  };
}
