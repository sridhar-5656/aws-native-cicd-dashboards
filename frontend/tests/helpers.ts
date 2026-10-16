import { vi } from "vitest";

export const INFO = {
  name: "DevOps Deployment Dashboard",
  version: "1.2.3",
  environment: "test",
  release_id: "1.2.3+abc1234",
  git_commit: "abc1234def5678",
  image_tag: "abc1234",
  build_time: null,
  started_at: "2026-01-01T00:00:00Z",
  python_version: "3.12.0",
  unavailable: ["pipeline_execution_status"],
};
export const STATUS = {
  status: "ok", uptime_seconds: 75, started_at: "2026-01-01T00:00:00Z",
  timestamp: "2026-01-01T00:01:15Z", checks: { startup_complete: true, frontend_assets: true },
};
export const LIVE = { status: "alive", timestamp: "2026-01-01T00:01:15Z" };
export const READY = { status: "ready", checks: { startup_complete: true }, timestamp: "2026-01-01T00:01:15Z" };

const json = (body: unknown, status = 200) =>
  Promise.resolve(new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } }));

export function mockFetch(overrides: Record<string, () => Promise<Response>> = {}) {
  const routes: Record<string, () => Promise<Response>> = {
    "/api/info": () => json(INFO),
    "/api/status": () => json(STATUS),
    "/health/live": () => json(LIVE),
    "/health/ready": () => json(READY),
    ...overrides,
  };
  const fn = vi.fn((input: RequestInfo | URL) => {
    const handler = routes[String(input)];
    return handler ? handler() : json({ error: "not found" }, 404);
  });
  vi.stubGlobal("fetch", fn);
  return fn;
}
export { json };
