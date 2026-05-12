# CIPPHttpTrigger Validation Guide for `cipp.kalleo.net`

Use the existing Application Insights telemetry for the deployed `cipp.kalleo.net` instance and the PR #6 query pack to compare the hot path before and after the `Measure-CippTask` change in this branch.

## What Changed

- Successful measured tasks no longer force an Application Insights flush on every request.
- Cancellation and failure cases still flush so the most important telemetry is retained.
- `Measure-CippTask` now tags events with `Outcome`, `ErrorType`, and `InvocationId` when available.

## Before/After Windows

- Before: the same business window used in the failure-anomaly investigation for `cipp.kalleo.net`.
- After: the same duration at the same time of day after deployment to `cipp.kalleo.net`.
- Compare at least one full business day if traffic is bursty.

## Queries To Reuse

Start with the query pack from the review repository and compare:

- `CIPPHttpTrigger` request duration p50/p95/p99
- failed request count and failure rate
- HTTP 499 count and rate
- `TaskCanceledException` count
- dependency failures correlated to `CIPPHttpTrigger`
- top slow operations

## Suggested KQL Checks

### Request duration trend

```kusto
requests
| where timestamp between (datetime(2026-05-12T11:30:00Z) .. datetime(2026-05-12T12:30:00Z))
| where name has "CIPPHttpTrigger" or operation_Name has "CIPPHttpTrigger"
| summarize Requests=count(), P50=percentile(duration, 50), P95=percentile(duration, 95), P99=percentile(duration, 99) by bin(timestamp, 5m)
| order by timestamp asc
```

### Failure and cancellation view

```kusto
exceptions
| where timestamp between (datetime(2026-05-12T11:30:00Z) .. datetime(2026-05-12T12:30:00Z))
| where type has "TaskCanceledException" or outerType has "TaskCanceledException"
| summarize Count=count() by bin(timestamp, 5m), type
| order by timestamp asc
```

### Cancellation-aware task telemetry

```kusto
customEvents
| where timestamp between (datetime(2026-05-12T11:30:00Z) .. datetime(2026-05-12T12:30:00Z))
| where name == "CIPP.TaskCompleted"
| where tostring(customDimensions.TaskName) has "CIPPHttpTrigger" or tostring(customDimensions.Endpoint) has "CIPPHttpTrigger"
| summarize Count=count(), Succeeded=countif(tostring(customDimensions.Outcome) == "Succeeded"), Failed=countif(tostring(customDimensions.Outcome) == "Failed"), Cancelled=countif(tostring(customDimensions.Outcome) == "Cancelled") by bin(timestamp, 5m)
| order by timestamp asc
```

## Success Criteria

- Lower p95/p99 on the hot path.
- Fewer 499s and timeout-driven cancellations.
- Fewer `TaskCanceledException` entries.
- No Azure resource or configuration changes.

## Rollback

- Revert the `Measure-CippTask` and `New-CippCoreRequest` changes.
- Re-run the same KQL windows to confirm the previous telemetry profile returns.
