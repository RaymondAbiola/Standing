import {defineChain} from "viem";
import {arbitrumSepolia} from "viem/chains";

/// Same canonical deployment on both Robinhood chains, confirmed onchain.
const MULTICALL3 = "0xcA11bde05977b3631167028862bE2a173976CA11" as const;

/// Robinhood Chain is not in viem's registry, so it is defined here from the
/// values in the repo README: chain 4663 mainnet, 46630 testnet.
export const robinhood = defineChain({
  id: 4663,
  name: "Robinhood Chain",
  nativeCurrency: {name: "Ether", symbol: "ETH", decimals: 18},
  rpcUrls: {
    default: {
      http: [
        process.env.NEXT_PUBLIC_ROBINHOOD_RPC || "https://rpc.mainnet.chain.robinhood.com",
      ],
    },
  },
  blockExplorers: {
    default: {name: "Blockscout", url: "https://robinhoodchain.blockscout.com"},
  },
  // Verified deployed at the canonical address. Without this viem refuses to
  // batch, and reading the hold list falls over.
  contracts: {multicall3: {address: MULTICALL3}},
});

export const robinhoodTestnet = defineChain({
  id: 46630,
  name: "Robinhood Chain Testnet",
  nativeCurrency: {name: "Ether", symbol: "ETH", decimals: 18},
  // Overridable like the others. The public endpoint is fine for a few
  // visitors, but the home page polls every twenty seconds from each browser,
  // so a rate limit on demo day needs to be fixable without a redeploy.
  rpcUrls: {
    default: {
      http: [
        process.env.NEXT_PUBLIC_ROBINHOOD_TESTNET_RPC || "https://rpc.testnet.chain.robinhood.com",
      ],
    },
  },
  blockExplorers: {
    default: {name: "Blockscout", url: "https://explorer.testnet.chain.robinhood.com"},
  },
  contracts: {multicall3: {address: MULTICALL3}},
});

export {arbitrumSepolia};
