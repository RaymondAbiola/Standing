"use client";

import {useEffect, useState} from "react";

/// Dark by default, matching the reference. The choice is a per-viewer
/// convenience, so a blocked or empty localStorage must not break the page.
export function ThemeToggle() {
  const [light, setLight] = useState(false);

  useEffect(() => {
    try {
      const saved = localStorage.getItem("standing:theme");
      if (saved === "light") setLight(true);
    } catch {}
  }, []);

  useEffect(() => {
    document.documentElement.setAttribute("data-theme", light ? "light" : "dark");
    try {
      localStorage.setItem("standing:theme", light ? "light" : "dark");
    } catch {}
  }, [light]);

  return (
    <button
      type="button"
      onClick={() => setLight((v) => !v)}
      aria-label={light ? "Switch to dark theme" : "Switch to light theme"}
      className="grid h-9 w-9 place-items-center rounded-full border transition-colors"
      style={{borderColor: "var(--line)", color: "var(--muted)"}}
    >
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        {light ? (
          <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z" strokeLinecap="round" />
        ) : (
          <>
            <circle cx="12" cy="12" r="4" />
            <path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5 19 19M19 5l-1.5 1.5M6.5 17.5 5 19" strokeLinecap="round" />
          </>
        )}
      </svg>
    </button>
  );
}
