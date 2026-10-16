export interface InfoResponse {
  name: string;
  version: string;
  environment: string;
  release_id: string;
  git_commit: string | null;
  image_tag: string | null;
  build_time: string | null;
  started_at: string;
  python_version: string;
  unavailable: string[];
}

export interface StatusResponse {
  status: "ok" | "degraded";
  uptime_seconds: number;
  started_at: string;
  timestamp: string;
  checks: Record<string, boolean> | null;
  request_count?: number;
  memory_mb?: number;
}

export interface LivenessResponse {
  status: "alive";
  timestamp: string;
}

export interface ReadinessResponse {
  status: "ready" | "not_ready";
  checks: Record<string, boolean>;
  timestamp: string;
}

/** Result of one API call. `error` is set for network/parse failures. */
export interface Fetched<T> {
  httpStatus: number | null;
  data: T | null;
  error: string | null;
  durationMs: number | null;
}

export type Section = "overview" | "deployment" | "health" | "endpoints";
