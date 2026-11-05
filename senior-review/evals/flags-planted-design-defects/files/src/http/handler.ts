import { createInvoice, parseAmount, InvoiceStore } from "../service/invoice.js";
import { RateProvider } from "../service/rates.js";

export async function postInvoice(store: InvoiceStore, providers: RateProvider[], body: any) {
  const currency = body.currency || "USD";
  try {
    const amount = parseAmount(body.amount);
    const inv = await createInvoice(store, providers, body.voyageId, amount, currency, body.discount ?? 0, undefined);
    return { status: 200, body: inv };
  } catch (e) {
    console.error("invoice failed", e);
    return { status: 500, body: { error: "internal error" } };
  }
}
