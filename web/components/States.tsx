import Link from "next/link";

import {Section} from "./ui";

export function NotConfigured() {
  return (
    <Section eyebrow="NOT CONFIGURED" title="No contract address set">
      <div className="panel px-5 py-6 text-[14px] leading-relaxed" style={{color: "var(--muted)"}}>
        <p>
          Set <code className="num">NEXT_PUBLIC_STANDING_ADDRESS</code> in <code className="num">web/.env.local</code>{" "}
          to the deployed Standing address, then restart the dev server.
        </p>
        <p className="mt-3">
          The Arbitrum Sepolia address is in the repository README. Copy{" "}
          <code className="num">.env.local.example</code> to get started.
        </p>
      </div>
    </Section>
  );
}

export function NotConnected({role}: {role: "payer" | "merchant"}) {
  return (
    <Section eyebrow="CONNECT" title={`Connect a wallet to act as a ${role}`}>
      <div className="panel px-5 py-6 text-[14px] leading-relaxed" style={{color: "var(--muted)"}}>
        <p>
          Everything on this page is read from the chain against your address. Use the connect button in the
          header, on Arbitrum Sepolia.
        </p>
        <p className="mt-3">
          <Link href="/" className="underline decoration-dotted underline-offset-4">
            Read how it works first
          </Link>
        </p>
      </div>
    </Section>
  );
}
