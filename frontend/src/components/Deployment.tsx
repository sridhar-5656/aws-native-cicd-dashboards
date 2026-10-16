import type { DashboardData } from "../hooks/useDashboardData";
import { CallState, Panel } from "./Panel";
import { Unavailable } from "./StatusBadge";

const LABELS: Record<string, string> = {
  pipeline_execution_status: "Pipeline execution status",
  aws_account_details: "AWS account details",
  ecs_task_metadata: "ECS task metadata",
};

export function Deployment({ data, loading }: { data: DashboardData; loading: boolean }) {
  return (
    <>
      <Panel title="Runtime-reported metadata" id="dep-runtime">
        <p className="muted">
          These values come from the running container’s <code>/api/info</code> response. Build-time values are
          injected by CodeBuild; a missing value means it was not provided.
        </p>
        <CallState call={data.info} loading={loading}>
          {(i) => (
            <dl className="kv">
              <div><dt>Version</dt><dd>{i.version}</dd></div>
              <div><dt>Release identifier</dt><dd><code>{i.release_id}</code></dd></div>
              <div><dt>Environment</dt><dd>{i.environment}</dd></div>
              <div><dt>Git commit</dt><dd>{i.git_commit ? <code>{i.git_commit}</code> : <Unavailable />}</dd></div>
              <div><dt>Container image tag</dt><dd>{i.image_tag ? <code>{i.image_tag}</code> : <Unavailable />}</dd></div>
              <div><dt>Build time (UTC)</dt><dd>{i.build_time ?? <Unavailable />}</dd></div>
              <div><dt>Application started</dt><dd>{new Date(i.started_at).toLocaleString()}</dd></div>
              <div><dt>Python runtime</dt><dd>{i.python_version}</dd></div>
            </dl>
          )}
        </CallState>
      </Panel>

      <Panel title="Not available from the runtime" id="dep-unavailable">
        <p className="muted">
          This app has no AWS API integration, so it does not show live pipeline or account data. Check AWS
          CodePipeline in the console for execution history.
        </p>
        <CallState call={data.info} loading={loading}>
          {(i) =>
            i.unavailable.length === 0 ? (
              <p className="muted">Nothing is listed as unavailable.</p>
            ) : (
              <ul className="plain-list">
                {i.unavailable.map((key) => (
                  <li key={key}>
                    {LABELS[key] ?? key} <Unavailable hint="Requires an AWS API integration that this app does not have" />
                  </li>
                ))}
              </ul>
            )
          }
        </CallState>
      </Panel>
    </>
  );
}
