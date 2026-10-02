"use client";

import {useRouter} from "next/navigation";
import {useState} from "react";

import {Button, Input} from "./ui";

/// Paste an address, see its record.
///
/// This is the claim the whole project rests on made checkable: a merchant is
/// meant to read a payer's history before agreeing to serve them, and a Visa
/// chargeback history is visible only to the issuing bank. So the lookup has to
/// work for a stranger with no wallet, or the claim is just an assertion.
export function AddressLookup({initial = ""}: {initial?: string}) {
  const router = useRouter();
  const [value, setValue] = useState(initial);

  const trimmed = value.trim();
  const valid = /^0x[0-9a-fA-F]{40}$/.test(trimmed);

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        if (valid) router.push(`/standing/${trimmed}`);
      }}
      className="flex flex-wrap items-start gap-3"
    >
      <div className="min-w-[260px] flex-1">
        <Input
          value={value}
          onChange={(e) => setValue(e.target.value)}
          placeholder="0x…"
          aria-label="Address to look up"
          spellCheck={false}
        />
        {trimmed.length > 0 && !valid ? (
          <p className="mt-2 text-[13px]" style={{color: "var(--color-warn)"}}>
            That is not a 20 byte address.
          </p>
        ) : null}
      </div>
      <Button type="submit" variant="primary" disabled={!valid}>
        Look up
      </Button>
    </form>
  );
}
