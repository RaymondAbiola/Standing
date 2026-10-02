import Link from "next/link";

import {LiveStats} from "@/components/LiveStats";
import {Mark} from "@/components/Mark";
import {MechanismDiagram} from "@/components/MechanismDiagram";

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
    title: "If taking money back is free, people will do it when nothing went wrong.",
    body: "Someone who can always pull a charge back has no reason to save it for real problems. They changed their mind, they found it cheaper, they are short this month. The merchant loses out every time, so no merchant would agree to it. That is why the right has to be earned instead of given. It opens up after three charges you let through without complaint, and you can never pull back more than a third of what you have actually paid. A brand new address cannot pull back anything at all, which is what stops someone starting over with a fresh wallet and doing it again.",
  },
];

export default function Home() {
  return (
    <>
      <section className="shell pt-6">
        <div className="panel aura px-6 py-16 text-center sm:px-10 sm:py-24">
          <h1 className="display rise mx-auto max-w-[19ch] text-[36px] sm:text-[56px]">
            Every charge waits until you say so.
          </h1>
          <p
            className="rise mx-auto mt-6 max-w-[46ch] text-[18px] font-semibold tracking-tight sm:text-[24px]"
            style={{"--d": "90ms"} as React.CSSProperties}
          >
            Standing orders for stablecoins, with recourse.
          </p>

          <div
            className="rise mt-9 flex flex-wrap items-center justify-center gap-3"
            style={{"--d": "180ms"} as React.CSSProperties}
          >
            <Link
              href="/payer"
              className="group inline-flex min-h-12 items-center gap-2 rounded-full px-6 text-[16px] font-medium transition-transform hover:-translate-y-0.5"
              style={{background: "var(--ink)", color: "var(--ground)"}}
            >
              I am a payer
              <span aria-hidden="true" className="transition-transform group-hover:translate-x-1">
                &rarr;
              </span>
            </Link>
            <Link
              href="/merchant"
              className="group inline-flex min-h-12 items-center gap-2 rounded-full border px-6 text-[16px] font-medium transition-all hover:-translate-y-0.5 hover:border-[var(--color-mint)]"
              style={{borderColor: "var(--line)", color: "var(--ink)"}}
            >
              I am a merchant
              <span aria-hidden="true" className="transition-transform group-hover:translate-x-1">
                &rarr;
              </span>
            </Link>
          </div>
        </div>

        <p className="mt-6 max-w-[64ch] text-[17px] leading-relaxed" style={{color: "var(--muted)"}}>
          Chargebacks do not exist onchain. Standing is what replaces them, without an arbiter.
        </p>

        <div className="mt-6">
          <MechanismDiagram />
        </div>
      </section>

      <LiveStats />

      {/*
        The four blocks below were a bare numbered list, which left a reader to
        infer what the sequence was even for. This names it: a problem, then the
        three pieces that answer it.
      */}
      <section className="shell pt-12">
        <p className="eyebrow">How it works</p>
        <h2 className="mt-3 max-w-[32ch] text-[30px] font-semibold leading-tight tracking-tight sm:text-[38px]">
          Why recurring payments break onchain, and what fixes them.
        </h2>
        <p className="mt-4 max-w-[68ch] text-[17px] leading-relaxed" style={{color: "var(--muted)"}}>
          Four steps: the problem, the permission that answers it, the pause that makes the permission
          safe to give, and the part that is easy to get wrong.
        </p>
      </section>

      <div className="shell pt-8">
        {STEPS.map((s) => (
          <article
            key={s.n}
            className="reveal grid gap-x-12 gap-y-4 border-t py-12 first:border-t-0 lg:grid-cols-[minmax(0,5fr)_minmax(0,6fr)]"
            style={{borderColor: "var(--line)"}}
          >
            <div>
              <p className="eyebrow">
                {s.n} &middot; {s.eyebrow}
              </p>
              <h3 className="mt-3 text-[26px] font-semibold leading-snug tracking-tight sm:text-[30px]">
                {s.title}
              </h3>
            </div>
            <p className="text-[17px] leading-relaxed lg:pt-7" style={{color: "var(--muted)"}}>
              {s.body}
            </p>
          </article>
        ))}
      </div>

      <section className="shell pb-4 pt-6">
        <p className="eyebrow">PICK A SIDE</p>
        <div className="mt-5 grid gap-5 sm:grid-cols-2">
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
    <Link href={href} className="panel lift group block px-6 py-7">
      <div className="flex items-center justify-between">
        <span className="flex items-center gap-2 text-[20px] font-semibold tracking-tight">
          <Mark size={18} />
          {title}
        </span>
        <span
          aria-hidden="true"
          className="transition-transform group-hover:translate-x-1"
          style={{color: "var(--color-mint)"}}
        >
          &rarr;
        </span>
      </div>
      <ul className="mt-4 space-y-2 text-[15px]" style={{color: "var(--muted)"}}>
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
