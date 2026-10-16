import type { DashboardData } from "../hooks/useDashboardData";
import { Panel } from "./Panel";
import { StatusBadge, Tone } from "./StatusBadge";

interface Row {
  label: string;
  description: string;
  tone: Tone;
  text: string;
}

function rows(d: DashboardData): Row[] {
  const out: Row[] = [];
  const call = (c: { error: string | null; httpStatus: number | null } | null, okText: string, okCode = 200) => {
    if (!c) return { tone: "neutral" as Tone, text: "Checking…" };
    if (c.error) return { tone: "bad" as Tone, text: c.error };
    return c.httpStatus === okCode
      ? { tone: "good" as Tone, text: okText }
      : { tone: "bad" as Tone, text: `HTTP ${c.httpStatus}` };
  };
  out.push({ label: "API health", description: "Backend answers requests (/api/status)", ...call(d.status, "OK") });
  out.push({ label: "Liveness", description: "Process is running (/health/live)", ...call(d.live, "Alive") });
  out.push({
    label: "Readiness",
    description: "Safe to receive traffic (/health/ready)",
    ...call(d.ready, "Ready"),
  });
  const fe = d.status?.data?.checks?.frontend_assets;
  out.push({
    label: "Frontend availability",
    description: "This page is being served, and the build exists on disk",
    tone: d.status === null ? "neutral" : fe === undefined ? "warn" : fe ? "good" : "warn",
    text: d.status === null ? "Checking…" : fe === undefined ? "Unknown" : fe ? "Available" : "Build not found on server",
  });
  const be = d.status;
  out.push({
    label: "Backend response",
    description: "Latest round trip to /api/status",
    tone: be?.durationMs != null ? "good" : be ? "bad" : "neutral",
    text: be?.durationMs != null ? `${be.durationMs} ms` : be ? "No response" : "Checking…",
  });
  return out;
}

export function SystemHealth({ data }: { data: DashboardData }) {
  const failing = data.ready?.data && data.ready.data.status !== "ready"
    ? Object.entries(data.ready.data.checks).filter(([, ok]) => !ok).map(([k]) => k)
    : [];
  return (
    <Panel title="System health" id="health-main">
      <ul className="stat-list">
        {rows(data).map((r) => (
          <li key={r.label}>
            <span>
              <strong>{r.label}</strong>
              <span className="muted block">{r.description}</span>
            </span>
            <StatusBadge tone={r.tone}>{r.text}</StatusBadge>
          </li>
        ))}
      </ul>
      {failing.length > 0 && (
        <p role="alert" className="error">Readiness checks failing: {failing.join(", ")}</p>
      )}
      <p className="muted">
        “Healthy” here means the container is healthy. ALB target health and ECS deployment health are separate and
        are viewed in the AWS console.
      </p>
    </Panel>
  );
}
