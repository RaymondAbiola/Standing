"use client";

import {useQueryClient} from "@tanstack/react-query";
import {useEffect} from "react";
import {useWaitForTransactionReceipt, useWriteContract} from "wagmi";

/// One write plus its receipt, with a refresh once it lands.
///
/// The invalidation is the point. Without it the page waits on the global
/// poll interval, so a confirmed transaction leaves the UI unchanged for
/// several seconds and every step looks like it failed. During a walkthrough
/// that reads as a broken app rather than a slow one.
export function useTx() {
  const queryClient = useQueryClient();
  const {writeContract, data: hash, isPending, error} = useWriteContract();
  const {isLoading, isSuccess} = useWaitForTransactionReceipt({hash});

  useEffect(() => {
    if (isSuccess) void queryClient.invalidateQueries();
  }, [isSuccess, hash, queryClient]);

  return {
    writeContract,
    hash,
    error,
    busy: isPending || isLoading,
    confirmed: isSuccess,
  };
}
