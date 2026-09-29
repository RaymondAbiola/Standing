import Link from "next/link";

import {Mark} from "@/components/Mark";

const STEPS = [
  {
    n: "01",
    eyebrow: "THE MISMATCH",
    title: "Chains can only push. Subscriptions run on pull.",
    body: "Every subscription works the same way: authorise once, and the payee draws funds repeatedly. Blockchains are push-only, because only the holder of a private key can move funds. So a merchant either begs customers to remember each month, or takes custody of their money.",
  },
  {
    n: "02",
    eyebrow: "THE MANDATE",
    title: "One permission slip, signed once.",
    body: "The payer signs terms stating who may charge, how much at most, and how often at most. The revoke button belongs to the payer alone and works in the same block, without the merchant's cooperation. There is a second kill switch too: the Permit2 allowance expires on its own.",
  },
  {
    n: "03",
    eyebrow: "THE WINDOW",
    title: "A charge lands in escrow, not in the merchant's account.",
    body: "Funds sit behind an unlock time. During that window the payer can reverse the charge. After it, anyone can settle it to the merchant. No arbiter, no adjudication, nobody to trust. The window itself is priced: a merchant with a long clean record waits hours, an unknown one waits days.",
  },
  {
    n: "04",
    eyebrow: "THE HARD PART",
    title: "A free reversal right is a free option.",
    body: "No merchant accepts one, so the right is earned rather than granted. It vests after three clean settlements, and its ceiling is a third of what the payer has settled cleanly. A fresh address holds no right at all, which is what removes the churn-and-claw attack instead of policing it.",
  },
];

export default function Home() {
  return (
    <>
      <section className="mx-auto max-w-[1000px] px-4 pt-6">
        <div className="panel overflow-hidden px-6 py-14 text-center sm:px-10 sm:py-20">
          <h1 className="display mx-auto max-w-[19ch] text-[30px] sm:text-[44px]">
            Every charge waits until you say so.
          </h1>
          <p className="mx-auto mt-5 max-w-[46ch] text-[16px] font-semibold tracking-tight sm:text-[20px]">
            Standing orders for stablecoins, with recourse.
          </p>

          <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
            <Link
              href="/payer"
              className="inline-flex min-h-11 items-center gap-2 rounded-full px-5 text-[13px] font-medium"
              style={{background: "var(--ink)", color: "var(--ground)"}}
            >
              I am a payer <span aria-hidden="true">&rarr;</span>
            </Link>
            <Link
              href="/merchant"
              className="inline-flex min-h-11 items-center gap-2 rounded-full border px-5 text-[13px] font-medium"
              style={{borderColor: "var(--line)", color: "var(--ink)"}}
            >
              I am a merchant <span aria-hidden="true">&rarr;</span>
            </Link>
          </div>
        </div>

        <p className="mt-5 text-[13px]" style={{color: "var(--muted)"}}>
          Chargebacks do not exist onchain. Standing is what replaces them, without an arbiter.
        </p>
      </section>

      <div className="mx-auto max-w-[1000px] px-4">
        {STEPS.map((s) => (
          <article key={s.n} className="border-t py-10 first:border-t-0" style={{borderColor: "var(--line)"}}>
            <p className="eyebrow">
              {s.n} &middot; {s.eyebrow}
            </p>
            <h2 className="mt-3 max-w-[30ch] text-[22px] font-semibold leading-snug tracking-tight sm:text-[26px]">
              {s.title}
            </h2>
            <p className="mt-3 max-w-[62ch] text-[15px] leading-relaxed" style={{color: "var(--muted)"}}>
              {s.body}
            </p>
          </article>
        ))}
      </div>

      <section className="mx-auto max-w-[1000px] px-4 pb-4 pt-6">
        <p className="eyebrow">PICK A SIDE</p>
        <div className="mt-4 grid gap-4 sm:grid-cols-2">
          <RoleCard
            href="/payer"
            title="Payer"
            lines={[
              "See your standing, ceiling and vesting progress",
              "Reverse a charge inside its window",
              "Revoke one mandate, or every mandate at once",
            ]}
          />
          <RoleCard
            href="/merchant"
            title="Merchant"
            lines={[
              "Charge a mandate and settle matured holds",
              "Watch your hold window shorten as you earn it",
              "Set who you will accept, before you agree to serve",
            ]}
          />
        </div>
      </section>
    </>
  );
}

function RoleCard({href, title, lines}: {href: string; title: string; lines: string[]}) {
  return (
    <Link href={href} className="panel group block px-5 py-6 transition-colors hover:border-[var(--color-mint)]">
      <div className="flex items-center justify-between">
        <span className="flex items-center gap-2 text-[17px] font-semibold tracking-tight">
          <Mark size={18} />
          {title}
        </span>
        <span aria-hidden="true" style={{color: "var(--muted)"}}>
          &rarr;
        </span>
      </div>
      <ul className="mt-4 space-y-2 text-[13px]" style={{color: "var(--muted)"}}>
        {lines.map((l) => (
          <li key={l} className="flex gap-2">
            <span aria-hidden="true" style={{color: "var(--color-mint)"}}>
              &middot;
            </span>
            {l}
          </li>
        ))}
      </ul>
    </Link>
  );
}
