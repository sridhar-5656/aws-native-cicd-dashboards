import { useCallback, useEffect, useRef, useState } from "react";
import { fetchJson } from "../api";
import type { Fetched, InfoResponse, LivenessResponse, ReadinessResponse, StatusResponse } from "../types";

export interface DashboardData {
  info: Fetched<InfoResponse> | null;
  status: Fetched<StatusResponse> | null;
  live: Fetched<LivenessResponse> | null;
  ready: Fetched<ReadinessResponse> | null;
}

const EMPTY: DashboardData = { info: null, status: null, live: null, ready: null };

export function useDashboardData() {
  const [data, setData] = useState<DashboardData>(EMPTY);
  const [loading, setLoading] = useState(true);
  const [lastRefreshed, setLastRefreshed] = useState<Date | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [liveUptimeSeconds, setLiveUptimeSeconds] = useState<number | null>(null);
  const mounted = useRef(true);
  const startedAtRef = useRef<number | null>(null);

  const refresh = useCallback(async (silent = false) => {
    if (!silent) {
      setLoading(true);
    }
    const [info, status, live, ready] = await Promise.all([
      fetchJson<InfoResponse>("/api/info"),
      fetchJson<StatusResponse>("/api/status"),
      fetchJson<LivenessResponse>("/health/live"),
      fetchJson<ReadinessResponse>("/health/ready"),
    ]);
    if (!mounted.current) return;
    setData({ info, status, live, ready });
    setLastRefreshed(new Date());

    if (status?.data?.started_at) {
      startedAtRef.current = new Date(status.data.started_at).getTime();
      setLiveUptimeSeconds(Math.max(0, Math.floor((Date.now() - startedAtRef.current) / 1000)));
    } else if (status?.data?.uptime_seconds != null) {
      setLiveUptimeSeconds(Math.floor(status.data.uptime_seconds));
    }

    if (!silent) {
      setLoading(false);
    }
  }, []);

  // Initial load
  useEffect(() => {
    mounted.current = true;
    void refresh(false);
    return () => {
      mounted.current = false;
    };
  }, [refresh]);

  // Live auto-polling every 3 seconds
  useEffect(() => {
    if (!autoRefresh) return;
    const interval = setInterval(() => {
      if (mounted.current) {
        void refresh(true);
      }
    }, 3000);
    return () => clearInterval(interval);
  }, [autoRefresh, refresh]);

  // Live ticking uptime counter every second
  useEffect(() => {
    const timer = setInterval(() => {
      if (startedAtRef.current) {
        setLiveUptimeSeconds(Math.max(0, Math.floor((Date.now() - startedAtRef.current) / 1000)));
      } else {
        setLiveUptimeSeconds((prev) => (prev !== null ? prev + 1 : null));
      }
    }, 1000);
    return () => clearInterval(timer);
  }, []);

  const toggleAutoRefresh = useCallback(() => {
    setAutoRefresh((prev) => !prev);
  }, []);

  return { data, loading, lastRefreshed, refresh, autoRefresh, toggleAutoRefresh, liveUptimeSeconds };
}

export type Health = "healthy" | "unhealthy" | "unreachable" | "unknown";

/** Overall backend health derived only from real responses. */
export function deriveHealth(d: DashboardData): Health {
  if (!d.live && !d.ready) return "unknown";
  const calls = [d.info, d.status, d.live, d.ready];
  if (calls.every((c) => c && c.error)) return "unreachable";
  if (d.live?.httpStatus === 200 && d.ready?.httpStatus === 200) return "healthy";
  return "unhealthy";
}

