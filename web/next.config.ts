import type {NextConfig} from "next";

const config: NextConfig = {
  reactStrictMode: true,

  webpack: (config) => {
    /*
     * wagmi/connectors has no subpath exports, so importing `injected` pulls
     * the whole barrel, which reaches Coinbase's account SDK and from there a
     * chain of x402 packages that are not resolvable. We never instantiate
     * that connector, so the branch is dead code: alias its root to an empty
     * module rather than installing transitive dependencies for a connector
     * the app does not offer.
     *
     * Revisit if a Coinbase or WalletConnect connector is ever added.
     */
    config.resolve.alias = {
      ...config.resolve.alias,
      "@base-org/account": false,
      "@coinbase/cdp-sdk": false,
    };
    return config;
  },
};

export default config;
