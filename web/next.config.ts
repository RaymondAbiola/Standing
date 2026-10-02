import path from "node:path";

import type {NextConfig} from "next";

const config: NextConfig = {
  reactStrictMode: true,

  /*
   * Without this, Next walks up and finds a stray lockfile in the home
   * directory, decides that is the workspace root, and traces the wrong files.
   * Harmless locally, but it makes a hosted build bundle from the wrong place.
   */
  outputFileTracingRoot: path.join(__dirname),

  webpack: (config) => {
    /*
     * wagmi/connectors has no subpath exports, so importing `injected` pulls
     * the whole barrel. That reaches Coinbase's account SDK, WalletConnect and
     * MetaMask's SDK, and from there packages that cannot resolve in a browser
     * build: a chain of x402 modules, and a React Native storage adapter.
     *
     * None of those connectors are offered by this app, so the branches are
     * dead code. Aliasing them to empty modules is correct, where installing
     * transitive dependencies for connectors we do not expose would not be.
     *
     * Revisit if a Coinbase, WalletConnect or MetaMask SDK connector is added.
     */
    config.resolve.alias = {
      ...config.resolve.alias,
      "@base-org/account": false,
      "@coinbase/cdp-sdk": false,
      "@react-native-async-storage/async-storage": false,
      "pino-pretty": false,
    };
    return config;
  },
};

export default config;
