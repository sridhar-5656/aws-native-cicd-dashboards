import type { Fetched } from "../types";

export function Panel({ title, id, children }: { title: string; id: string; children: React.ReactNode }) {
  return (
    <section className="panel" aria-labelledby={id}>
      <h2 id={id}>{title}</h2>
      {children}
    </section>
  );
}

/** Shows an error / loading message for a failed or pending call, else children. */
export function CallState<T>({
  call,
  loading,
  children,
}: {
  call: Fetched<T> | null;
  loading: boolean;
  children: (data: T) => React.ReactNode;
}) {
  if (!call) {
    return <p className="muted">{loading ? "Loading…" : "No data yet. Select Refresh to load it."}</p>;
  }
  if (call.error || call.data === null) {
    return (
      <p role="alert" className="error">
        {call.error ?? "Empty response"}. Check that the backend container is running, then select Refresh.
      </p>
    );
  }
  return <>{children(call.data)}</>;
}
