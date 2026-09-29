/// Minimal ABIs for the two contracts a payer has to touch before a mandate
/// can be charged: the token, and Permit2.

export const demoTokenAbi = [
  {
    type: "function",
    name: "mint",
    stateMutability: "nonpayable",
    inputs: [
      {name: "to", type: "address"},
      {name: "amount", type: "uint256"},
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      {name: "spender", type: "address"},
      {name: "amount", type: "uint256"},
    ],
    outputs: [{type: "bool"}],
  },
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{name: "who", type: "address"}],
    outputs: [{type: "uint256"}],
  },
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      {name: "owner", type: "address"},
      {name: "spender", type: "address"},
    ],
    outputs: [{type: "uint256"}],
  },
] as const;

/// The slice of Permit2's AllowanceTransfer a payer calls directly. Standing
/// pulls through this, so the allowance here is the second of the payer's two
/// kill switches: it expires on its own, with no transaction needed.
export const permit2Abi = [
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      {name: "token", type: "address"},
      {name: "spender", type: "address"},
      {name: "amount", type: "uint160"},
      {name: "expiration", type: "uint48"},
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      {name: "user", type: "address"},
      {name: "token", type: "address"},
      {name: "spender", type: "address"},
    ],
    outputs: [
      {name: "amount", type: "uint160"},
      {name: "expiration", type: "uint48"},
      {name: "nonce", type: "uint48"},
    ],
  },
] as const;

export const PERMIT2_ADDRESS = "0x000000000022D473030F116dDEE9F6B43aC78BA3" as const;

/// Must match MandateLib.MANDATE_TYPEHASH exactly, field order included. The
/// contract encodes the ChargeKind enum as uint8, so it is declared that way
/// here rather than as a named type.
export const MANDATE_TYPES = {
  Mandate: [
    {name: "payer", type: "address"},
    {name: "merchant", type: "address"},
    {name: "token", type: "address"},
    {name: "maxAmount", type: "uint256"},
    {name: "minInterval", type: "uint64"},
    {name: "startsAt", type: "uint64"},
    {name: "expiresAt", type: "uint64"},
    {name: "maxCharges", type: "uint32"},
    {name: "chargeKind", type: "uint8"},
    {name: "salt", type: "bytes32"},
  ],
} as const;

export type MandateStruct = {
  payer: `0x${string}`;
  merchant: `0x${string}`;
  token: `0x${string}`;
  maxAmount: bigint;
  minInterval: bigint;
  startsAt: bigint;
  expiresAt: bigint;
  maxCharges: number;
  chargeKind: number;
  salt: `0x${string}`;
};

/// A fresh salt per mandate. Required, not cosmetic: the mandate id is the
/// EIP-712 struct hash, records are never cleared, and identical terms would
/// collide with a revoked mandate and be refused.
export function randomSalt(): `0x${string}` {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return `0x${Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")}` as `0x${string}`;
}
