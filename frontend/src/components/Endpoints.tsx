import { useState } from "react";
import { fetchJson } from "../api";
import type { Fetched } from "../types";
import { Panel } from "./Panel";

const ENDPOINTS = [
  { path: "/", note: "Home (HTML in the browser, JSON with Accept: application/json)" },
  { path: "/health", note: "Basic health" },
  { path: "/health/live", note: "Liveness" },
  { path: "/health/ready", note: "Readiness (503 when not ready)" },
  { path: "/api/info", note: "Version and release metadata" },
  { path: "/api/status", note: "Uptime and checks" },
];

export function Endpoints() {
  const [results, setResults] = useState<Record<string, Fetched<unknown> | "loading">>({});

  async function tryIt(path: string) {
    setResults((r) => ({ ...r, [path]: "loading" }));
    const res = await fetchJson<unknown>(path);
    setResults((r) => ({ ...r, [path]: res }));
  }

  return (
    <Panel title="API endpoints" id="endpoints-main">
      <p className="muted">Each button calls the real endpoint on this server and shows the response.</p>
      <ul className="endpoint-list">
        {ENDPOINTS.map(({ path, note }) => {
          const res = results[path];
          return (
            <li key={path}>
              <div className="endpoint-row">
                <span>
                  <code>GET {path}</code>
                  <span className="muted block">{note}</span>
                </span>
                <button type="button" onClick={() => tryIt(path)} aria-label={`Call GET ${path}`}>
                  {res === "loading" ? "Calling…" : "Call"}
                </button>
              </div>
              {res && res !== "loading" && (
                <div aria-live="polite">
                  <p className="muted">
                    {res.error ? `Failed: ${res.error}` : `HTTP ${res.httpStatus} in ${res.durationMs} ms`}
                  </p>
                  {res.data !== null && <pre tabIndex={0}>{JSON.stringify(res.data, null, 2)}</pre>}
                </div>
              )}
            </li>
          );
        })}
      </ul>
    </Panel>
  );
}
