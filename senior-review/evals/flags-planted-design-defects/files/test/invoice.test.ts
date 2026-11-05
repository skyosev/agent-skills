import { describe, it, expect, vi } from "vitest";
import { createInvoice } from "../src/service/invoice.js";

describe("createInvoice", () => {
  it("saves the converted invoice", async () => {
    const store = { save: vi.fn().mockResolvedValue(undefined) };
    const provider = { name: "p", fetch: vi.fn().mockResolvedValue(2) };
    await createInvoice(store, [provider], "v1", 100, "EUR", 0, undefined);
    expect(store.save).toHaveBeenCalledTimes(1);
  });
});
