import { afterEach, describe, expect, it, vi } from "vitest";
import { fetchJson } from "../src/api";
import { json } from "./helpers";

afterEach(() => vi.unstubAllGlobals());

describe("fetchJson", () => {
  it("returns data and status on success", async () => {
    vi.stubGlobal("fetch", vi.fn(() => json({ a: 1 })));
    const r = await fetchJson<{ a: number }>("/x");
    expect(r).toMatchObject({ httpStatus: 200, data: { a: 1 }, error: null });
  });

  it("keeps JSON bodies of non-2xx responses as data", async () => {
    vi.stubGlobal("fetch", vi.fn(() => json({ status: "not_ready" }, 503)));
    const r = await fetchJson<{ status: string }>("/health/ready");
    expect(r.httpStatus).toBe(503);
    expect(r.data?.status).toBe("not_ready");
    expect(r.error).toBeNull();
  });

  it("reports network failures", async () => {
    vi.stubGlobal("fetch", vi.fn(() => Promise.reject(new TypeError("boom"))));
    const r = await fetchJson("/x");
    expect(r.error).toMatch(/Could not reach/);
    expect(r.data).toBeNull();
  });

  it("reports non-JSON bodies", async () => {
    vi.stubGlobal("fetch", vi.fn(() => Promise.resolve(new Response("<html>", { status: 502 }))));
    const r = await fetchJson("/x");
    expect(r.error).toMatch(/not valid JSON/);
    expect(r.httpStatus).toBe(502);
  });
});
