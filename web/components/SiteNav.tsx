"use client";

import Link from "next/link";
import {usePathname} from "next/navigation";

import {Mark} from "./Mark";
import {ConnectButton} from "./ConnectButton";
import {ThemeToggle} from "./ThemeToggle";

const LINKS = [
  {href: "/payer", label: "Payer"},
  {href: "/merchant", label: "Merchant"},
  {href: "/standing", label: "Look up"},
];

export function SiteNav() {
  const path = usePathname();

  return (
    <header
      className="sticky top-0 z-40 border-b backdrop-blur"
      style={{borderColor: "var(--line)", background: "color-mix(in srgb, var(--ground) 82%, transparent)"}}
    >
      <nav className="shell flex items-center gap-6 py-4">
        <Link
          href="/"
          className="flex shrink-0 items-center gap-2.5 text-[21px] font-semibold tracking-tight"
        >
          <Mark size={28} />
          Standing
        </Link>

        <div className="flex items-center gap-4 text-[15px]">
          {LINKS.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className="transition-opacity hover:opacity-100"
              style={{color: path === l.href ? "var(--ink)" : "var(--muted)", opacity: path === l.href ? 1 : 0.9}}
            >
              {l.label}
            </Link>
          ))}
        </div>

        <div className="ml-auto flex items-center gap-2">
          <ThemeToggle />
          <ConnectButton />
        </div>
      </nav>
    </header>
  );
}
