import type {Metadata} from "next";
import {Geist, Geist_Mono} from "next/font/google";

import {Providers} from "./providers";
import {Mark} from "@/components/Mark";
import {SiteNav} from "@/components/SiteNav";
import "./globals.css";

const geist = Geist({subsets: ["latin"], variable: "--font-geist", weight: ["400", "500", "600", "700"]});
const geistMono = Geist_Mono({subsets: ["latin"], variable: "--font-geist-mono", weight: ["400", "500"]});

export const metadata: Metadata = {
  title: "Standing",
  description: "Standing orders for stablecoins, with recourse.",
};

export default function RootLayout({children}: {children: React.ReactNode}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={`${geist.variable} ${geistMono.variable}`}>
        <Providers>
          <SiteNav />
          <main>{children}</main>
          <footer className="mx-auto max-w-[1000px] px-4 pb-12 pt-14">
            <div
              className="flex flex-wrap items-center justify-between gap-4 border-t pt-6 text-[13px]"
              style={{borderColor: "var(--line)", color: "var(--muted)"}}
            >
              <span
                className="flex items-center gap-2 text-[15px] font-semibold tracking-tight"
                style={{color: "var(--ink)"}}
              >
                <Mark size={20} />
                Standing
              </span>
              <span className="eyebrow">Arbitrum Sepolia &middot; Robinhood Chain</span>
              <a
                href="https://github.com"
                className="underline decoration-dotted underline-offset-4 hover:no-underline"
              >
                Contracts are unaudited
              </a>
            </div>
          </footer>
        </Providers>
      </body>
    </html>
  );
}
