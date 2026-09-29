"use client";

import {createConfig, http} from "wagmi";
import {injected} from "wagmi/connectors";

import {arbitrumSepolia, robinhood, robinhoodTestnet} from "./chains";

/// Injected only, deliberately. WalletConnect and Reown AppKit both need a
/// project id from their dashboards, and nothing here should be blocked on
/// waiting for one. Adding a connector later is a one-line change.
export const wagmiConfig = createConfig({
  chains: [arbitrumSepolia, robinhood, robinhoodTestnet],
  connectors: [injected()],
  transports: {
    [arbitrumSepolia.id]: http(process.env.NEXT_PUBLIC_ARBITRUM_SEPOLIA_RPC),
    [robinhood.id]: http(),
    [robinhoodTestnet.id]: http(),
  },
  ssr: true,
});

export const STANDING_ADDRESS = (process.env.NEXT_PUBLIC_STANDING_ADDRESS ||
  "0x0000000000000000000000000000000000000000") as `0x${string}`;

export const isConfigured = STANDING_ADDRESS !== "0x0000000000000000000000000000000000000000";
