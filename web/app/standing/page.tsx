import {AddressLookup} from "@/components/AddressLookup";
import {Section} from "@/components/ui";

export const metadata = {
  title: "Look up standing",
  description: "Any address's payment record, on both deployments.",
};

export default function LookupPage() {
  return (
    <Section eyebrow="LOOK UP" title="Any address, both sides of its record">
      <div className="panel px-5 py-6">
        <p className="max-w-[64ch] text-[16px] leading-relaxed" style={{color: "var(--muted)"}}>
          Standing is public. A merchant is meant to read a payer&apos;s history before agreeing to serve
          them, which is the thing a card network structurally cannot offer, because that data is its moat.
          No wallet needed here.
        </p>
        <div className="mt-5">
          <AddressLookup />
        </div>
      </div>
    </Section>
  );
}
