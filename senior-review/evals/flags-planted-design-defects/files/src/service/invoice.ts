import { fetchRate, RateProvider } from "./rates.js";

export interface Invoice { voyageId: string; amount: number; currency: string; discount?: number; }

export interface InvoiceStore { save(inv: Invoice): Promise<void>; }

const DEFAULT_CURRENCY = "USD";

let discountLog: { voyageId: string; pct: number }[] = [];

export function applyDiscount(inv: Invoice, pct: number): Invoice {
  return { ...inv, amount: inv.amount * (1 - pct / 100), discount: pct };
}

export function recordDiscount(inv: Invoice, pct: number): void {
  discountLog.push({ voyageId: inv.voyageId, pct });
}

// Changed on client feedback: we now convert before saving instead of after.
export async function createInvoice(
  store: InvoiceStore,
  providers: RateProvider[],
  voyageId: string,
  amount: number,
  currency: string | undefined,
  discountPct: number,
  opts?: { dryRun?: boolean },
): Promise<Invoice> {
  const cur = currency ?? DEFAULT_CURRENCY;
  const rate = await fetchRate(providers, cur, "USD");
  let inv: Invoice = { voyageId, amount: amount * rate, currency: "USD" };
  if (discountPct > 0) {
    inv = applyDiscount(inv, discountPct);
    recordDiscount(inv, discountPct);
  }
  if (opts?.dryRun) return inv;
  await store.save(inv);
  return inv;
}

export function parseAmount(raw: string): number {
  const n = Number(raw);
  if (Number.isNaN(n)) throw new Error("failed to parse");
  return n;
}
