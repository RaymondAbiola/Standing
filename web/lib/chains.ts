import {defineChain} from "viem";
import {arbitrumSepolia} from "viem/chains";

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
});

export const robinhoodTestnet = defineChain({
  id: 46630,
  name: "Robinhood Chain Testnet",
  nativeCurrency: {name: "Ether", symbol: "ETH", decimals: 18},
  rpcUrls: {default: {http: ["https://rpc.testnet.chain.robinhood.com"]}},
  blockExplorers: {
    default: {name: "Blockscout", url: "https://explorer.testnet.chain.robinhood.com"},
  },
});

export {arbitrumSepolia};
