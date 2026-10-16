import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import App from "../src/App";
import { json, mockFetch } from "./helpers";

afterEach(() => vi.unstubAllGlobals());

describe("App", () => {
  it("shows a loading state, then real release data", async () => {
    mockFetch();
    render(<App />);
    expect(screen.getByText("Loading…")).toBeInTheDocument();
    expect(await screen.findByText("v1.2.3")).toBeInTheDocument();
    expect(screen.getByText("abc1234")).toBeInTheDocument();
    expect(screen.getAllByText("Healthy").length).toBeGreaterThan(0);
  });

  it("shows an error state when the API is unreachable", async () => {
    vi.stubGlobal("fetch", vi.fn(() => Promise.reject(new TypeError("network down"))));
    render(<App />);
    expect((await screen.findAllByRole("alert"))[0]).toHaveTextContent(/Could not reach the API/);
    expect(screen.getAllByText("API unreachable").length).toBeGreaterThan(0);
  });

  it("reports not-ready when readiness returns 503", async () => {
    mockFetch({
      "/health/ready": () =>
        json({ status: "not_ready", checks: { startup_complete: true, frontend_assets: false }, timestamp: "t" }, 503),
    });
    render(<App />);
    await screen.findByText("v1.2.3");
    await userEvent.click(screen.getByRole("button", { name: "System health" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("frontend_assets");
  });

  it("marks missing build metadata as Unavailable instead of inventing it", async () => {
    mockFetch();
    render(<App />);
    await screen.findByText("v1.2.3");
    await userEvent.click(screen.getByRole("button", { name: "Deployment" }));
    const buildTime = (await screen.findByText("Build time (UTC)")).parentElement!;
    expect(buildTime).toHaveTextContent("Unavailable");
    expect(screen.getByText("Pipeline execution status")).toBeInTheDocument();
  });

  it("refreshes on demand", async () => {
    const fetchMock = mockFetch();
    render(<App />);
    await screen.findByText("v1.2.3");
    const before = fetchMock.mock.calls.length;
    await userEvent.click(screen.getByRole("button", { name: "Refresh" }));
    await waitFor(() => expect(fetchMock.mock.calls.length).toBe(before * 2));
  });

  it("navigates between sections and can call an endpoint", async () => {
    mockFetch();
    render(<App />);
    await screen.findByText("v1.2.3");
    await userEvent.click(screen.getByRole("button", { name: "API endpoints" }));
    await userEvent.click(screen.getByRole("button", { name: "Call GET /health/live" }));
    expect(await screen.findByText(/HTTP 200/)).toBeInTheDocument();
  });
});
