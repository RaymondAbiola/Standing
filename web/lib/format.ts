/// USDC-style six decimals throughout, which is what the stablecoins Standing
/// targets actually use.
export const DECIMALS = 6;

export function formatAmount(raw: bigint | undefined, decimals = DECIMALS): string {
  if (raw === undefined) return "—";
  const base = 10n ** BigInt(decimals);
  const whole = raw / base;
  const frac = raw % base;
  const frac2 = (frac * 100n) / base;
  return `${whole.toLocaleString("en-US")}.${frac2.toString().padStart(2, "0")}`;
}

export function parseAmount(text: string, decimals = DECIMALS): bigint {
  const [whole = "0", frac = ""] = text.trim().split(".");
  const padded = (frac + "0".repeat(decimals)).slice(0, decimals);
  return BigInt(whole || "0") * 10n ** BigInt(decimals) + BigInt(padded || "0");
}

/// Compact durations, because a countdown reading "2 days 4 hours 13 minutes"
/// is worse than "2d 4h" in a table row.
export function formatDuration(seconds: bigint | number | undefined): string {
  if (seconds === undefined) return "—";
  let s = Number(seconds);
  if (s <= 0) return "now";

  const d = Math.floor(s / 86400);
  s -= d * 86400;
  const h = Math.floor(s / 3600);
  s -= h * 3600;
  const m = Math.floor(s / 60);

  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m`;
  return `${Math.floor(s)}s`;
}

export function shortAddress(a: string | undefined): string {
  if (!a) return "—";
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

export const HOLD_STATUS = ["None", "Held", "Finalized", "Reversed"] as const;

export const REVERSAL_BLOCK = [
  "None",
  "Hold not open",
  "Not your hold",
  "Window closed",
  "Not vested",
  "Suspended",
  "Above ceiling",
] as const;

export const CHARGE_BLOCK = [
  "None",
  "Not live",
  "Too soon",
  "Charge limit reached",
  "Amount is zero",
  "Above cap",
] as const;
