import { useState } from "react";
import { Deployment } from "./components/Deployment";
import { Endpoints } from "./components/Endpoints";
import { Overview } from "./components/Overview";
import { StatusBadge } from "./components/StatusBadge";
import { SystemHealth } from "./components/SystemHealth";
import { deriveHealth, useDashboardData } from "./hooks/useDashboardData";
import type { Section } from "./types";

const SECTIONS: { id: Section; label: string }[] = [
  { id: "overview", label: "Overview" },
  { id: "deployment", label: "Deployment" },
  { id: "health", label: "System health" },
  { id: "endpoints", label: "API endpoints" },
];

export default function App() {
  const [section, setSection] = useState<Section>("overview");
  const { data, loading, lastRefreshed, refresh, autoRefresh, toggleAutoRefresh, liveUptimeSeconds } =
    useDashboardData();
  const health = deriveHealth(data);
  const tone = health === "healthy" ? "good" : health === "unknown" ? "neutral" : "bad";
  const label = { healthy: "Healthy", unhealthy: "Unhealthy", unreachable: "API unreachable", unknown: "Checking…" }[health];

  return (
    <div className="shell">
      <header className="topbar">
        <div className="brand">
          <h1>DevOps Deployment Dashboard</h1>
          <p className="muted">Live view of the container you are connected to</p>
        </div>
        <div className="topbar__actions">
          <StatusBadge tone={tone}>{label}</StatusBadge>
          <button
            type="button"
            className={`live-btn ${autoRefresh ? "live-btn--active" : ""}`}
            onClick={toggleAutoRefresh}
            title={autoRefresh ? "Click to pause live capturing" : "Click to resume live capturing"}
          >
            <span className={autoRefresh ? "live-dot live-dot--pulse" : "paused-dot"} />
            {autoRefresh ? "Live (3s)" : "Paused"}
          </button>
          <button type="button" className="primary" onClick={() => void refresh(false)} disabled={loading}>
            {loading ? "Refreshing…" : "Refresh"}
          </button>
        </div>
      </header>

      <nav aria-label="Dashboard sections" className="tabs">
        {SECTIONS.map((s) => (
          <button
            key={s.id}
            type="button"
            aria-current={section === s.id ? "page" : undefined}
            onClick={() => setSection(s.id)}
          >
            {s.label}
          </button>
        ))}
      </nav>

      <main>
        <div className="refreshed-bar">
          <span className="live-status">
            <span className={autoRefresh ? "live-dot live-dot--pulse" : "paused-dot"} />
            {autoRefresh ? "Live updates active (capturing every 3s)" : "Live updates paused"}
          </span>
          <span className="muted" aria-live="polite">
            {lastRefreshed ? `Last refreshed ${lastRefreshed.toLocaleTimeString()}` : "Not refreshed yet"}
          </span>
        </div>
        {section === "overview" && (
          <Overview data={data} health={health} loading={loading} liveUptimeSeconds={liveUptimeSeconds} />
        )}
        {section === "deployment" && <Deployment data={data} loading={loading} />}
        {section === "health" && <SystemHealth data={data} />}
        {section === "endpoints" && <Endpoints />}
      </main>

      <footer className="muted">
        Served by FastAPI from the same container. No simulated metrics: every value above is a real API response.
      </footer>
    </div>
  );
}
