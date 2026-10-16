export type Tone = "good" | "bad" | "warn" | "neutral";

const ICON: Record<Tone, string> = { good: "✓", bad: "✕", warn: "!", neutral: "–" };

/** Status is conveyed by text + icon, never by colour alone. */
export function StatusBadge({ tone, children }: { tone: Tone; children: React.ReactNode }) {
  return (
    <span className={`badge badge--${tone}`}>
      <span aria-hidden="true" className="badge__icon">{ICON[tone]}</span>
      {children}
    </span>
  );
}

export function Unavailable({ hint }: { hint?: string }) {
  return (
    <span className="unavailable" title={hint ?? "Not provided to this deployment"}>
      Unavailable
    </span>
  );
}
