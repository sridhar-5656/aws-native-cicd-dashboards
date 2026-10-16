import type { Fetched } from "./types";

/**
 * Fetch JSON from a relative URL. A non-2xx response that still returns JSON
 * (e.g. readiness 503) is returned as data with its httpStatus, not as an error.
 * Network failures and non-JSON bodies are reported through `error`.
 */
export async function fetchJson<T>(path: string, timeoutMs = 8000): Promise<Fetched<T>> {
  const started = performance.now();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(path, {
      headers: { Accept: "application/json" },
      cache: "no-store",
      signal: controller.signal,
    });
    const durationMs = Math.round(performance.now() - started);
    let data: T | null = null;
    try {
      data = (await response.json()) as T;
    } catch {
      return {
        httpStatus: response.status,
        data: null,
        error: `Response was not valid JSON (HTTP ${response.status})`,
        durationMs,
      };
    }
    return { httpStatus: response.status, data, error: null, durationMs };
  } catch (err) {
    const aborted = err instanceof DOMException && err.name === "AbortError";
    return {
      httpStatus: null,
      data: null,
      error: aborted ? `Request timed out after ${timeoutMs / 1000}s` : "Could not reach the API",
      durationMs: null,
    };
  } finally {
    clearTimeout(timer);
  }
}
