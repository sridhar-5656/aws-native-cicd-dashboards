import type { DashboardData, Health } from "../hooks/useDashboardData";
import { CallState, Panel } from "./Panel";
import { StatusBadge, Unavailable } from "./StatusBadge";

const HEALTH_LABEL: Record<Health, string> = {
  healthy: "Healthy",
  unhealthy: "Unhealthy",
  unreachable: "API unreachable",
  unknown: "Checking…",
};

export function Overview({
  data,
  health,
  loading,
  liveUptimeSeconds,
}: {
  data: DashboardData;
  health: Health;
  loading: boolean;
  liveUptimeSeconds?: number | null;
}) {
  const apiTone = health === "healthy" ? "good" : health === "unknown" ? "neutral" : "bad";
  const uptime = liveUptimeSeconds ?? data.status?.data?.uptime_seconds ?? null;

  return (
    <>
      <Panel title="Current release" id="ov-release">
        <CallState call={data.info} loading={loading}>
          {(info) => (
            <div className="ticket">
              <div>
                <p className="ticket__version">v{info.version}</p>
                <p className="muted">{info.name}</p>
              </div>
              <dl className="ticket__meta">
                <div><dt>Release</dt><dd><code>{info.release_id}</code></dd></div>
                <div><dt>Environment</dt><dd>{info.environment}</dd></div>
                <div>
                  <dt>Commit</dt>
                  <dd>{info.git_commit ? <code>{info.git_commit.slice(0, 7)}</code> : <Unavailable />}</dd>
                </div>
              </dl>
            </div>
          )}
        </CallState>
      </Panel>

      <Panel title="At a glance" id="ov-glance">
        <ul className="stat-list">
          <li>
            <span>Application health</span>
            <StatusBadge tone={apiTone}>{HEALTH_LABEL[health]}</StatusBadge>
          </li>
          <li>
            <span>API connectivity</span>
            {data.info === null ? (
              <StatusBadge tone="neutral">Checking…</StatusBadge>
            ) : data.info.error ? (
              <StatusBadge tone="bad">Not connected</StatusBadge>
            ) : (
              <StatusBadge tone="good">Connected ({data.info.durationMs} ms)</StatusBadge>
            )}
          </li>
          <li>
            <span>Process started</span>
            <span>{data.status?.data ? new Date(data.status.data.started_at).toLocaleString() : <Unavailable />}</span>
          </li>
          <li>
            <span>Live Uptime</span>
            <span className="live-value">{uptime != null ? formatUptime(uptime) : <Unavailable />}</span>
          </li>
          {data.status?.data?.memory_mb != null && (
            <li>
              <span>Process Memory (RSS)</span>
              <span className="live-value">{data.status.data.memory_mb} MB</span>
            </li>
          )}
          {data.status?.data?.request_count != null && (
            <li>
              <span>Total Requests Handled</span>
              <span className="live-value">{data.status.data.request_count.toLocaleString()}</span>
            </li>
          )}
          {data.status?.data?.timestamp && (
            <li>
              <span>Server Timestamp</span>
              <span className="muted">{new Date(data.status.data.timestamp).toLocaleTimeString()}</span>
            </li>
          )}
        </ul>
      </Panel>
    </>
  );
}

export function formatUptime(seconds: number): string {
  const s = Math.floor(seconds);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s % 60}s`;
  return `${s}s`;
}
