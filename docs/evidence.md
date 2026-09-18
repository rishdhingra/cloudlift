# CloudLift verification record

## AWS demonstration: September 18, 2026

Region: `us-east-1`. Application commit deployed by GitHub Actions: `29336d8d24c8df5a514c5f9e747f71778908d01c`. Terraform fixes made during the session are recorded separately in the repository history.

Initial image: `public.ecr.aws/c5t6h8t1/cloudlift-api@sha256:828db4ae4d1b2ed096037b757430be4cf009f0d154ce161c407a5aa04907c60c`.

GitHub-deployed image: `public.ecr.aws/c5t6h8t1/cloudlift-api@sha256:d2194b2cb65a3e07afb8e6d1e16be765404b2a760c9afbdb42d6deeb78b2e21d`.

Both running tasks used revision `cloudlift-api:2`, had healthy container status, and ran in separate Availability Zones when captured at 21:01:49 UTC. See [deployed tasks](evidence/aws-deployed-tasks.json).

## Integration and bounded load

[Before deployment](evidence/aws-integration.json) and [after deployment](evidence/aws-integration-after-deploy.json): nine API checks passed each time. Tests exercised database connectivity, input validation, customer insertion, duplicate handling, listing, and count. Data was synthetic.

| Configuration | Requests | Concurrent workers | Successes | Failures | p50 | p95 | Total time |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [Two tasks](evidence/aws-load-two-tasks.json) | 100 | 5 | 100 | 0 | 57.82 ms | 125.35 ms | 1.47 s |
| [One task](evidence/aws-load-one-task.json) | 100 | 5 | 100 | 0 | 57.19 ms | 63.95 ms | 1.23 s |

Each sample was run once from the user's laptop against `/health`, which includes a database query. Network and connection setup affect these measurements. These small samples verify successful requests at the tested load, not throughput limits, production latency, or a scaling improvement. Task count was changed manually and restored to two.

## Container replacement

One identified CloudLift task was stopped at 20:38:10 UTC while health probes ran. ECS launched a different task automatically. At 20:39:32 UTC, both load-balancer targets were healthy in different AZs. The 82-second interval is an upper bound to our observation of recovery, not an exact startup measurement.

All 281 probes passed during the approximately five-minute observation. The original customer (ID 1) remained unchanged. This demonstrates recovery from a controlled task stop, not an AZ outage or every possible failure mode.

Evidence: [stop time](evidence/aws-task-stop-time.txt), [stop response](evidence/aws-task-stop.json), [health check time](evidence/aws-task-recovery-time.txt), [targets](evidence/aws-task-recovery-targets.json), [probes](evidence/aws-task-recovery-probes.jsonl), [customer](evidence/aws-customers-after-task-recovery.json).

## Database failover

RDS was available with a primary in `us-east-1a` and standby in `us-east-1b`. A forced failover was requested at 20:43:48 UTC. Subsequent checks confirmed the primary in `us-east-1b`, the standby in `us-east-1a`, and the original customer unchanged.

The approximately ten-minute monitor recorded 277 probes: 272 passed and five consecutive probes failed. Each failed request reached approximately the five-second client timeout. There were **40.81 seconds between the last successful response before the failures and the first successful response afterward**. This is an observed response gap, not exact database downtime; requests were sampled with two-second pauses and the first recovered request took approximately 3.62 seconds. No zero-downtime claim is made.

Evidence: [before](evidence/aws-db-before-failover.json), [request time](evidence/aws-db-failover-time.txt), [request response](evidence/aws-db-failover-request.json), [after](evidence/aws-db-after-failover.json), [probes](evidence/aws-db-failover-probes.jsonl), [retained customer](evidence/aws-customers-after-db-failover.json).

## GitHub Actions and observability

[Deploy existing demo, run 35393411374, attempt 3](https://github.com/rishdhingra/cloudlift/actions/runs/35393411374) succeeded. GitHub authenticated through OIDC, published an immutable image, updated the ECS task definition, and waited for service stability. Post-deployment integration tests passed.

CloudWatch exports contain [29 CPU data points](evidence/aws-cloudwatch-cpu.json), [29 memory data points](evidence/aws-cloudwatch-memory.json), [28 request-count data points](evidence/aws-cloudwatch-requests.json), and [20 log events](evidence/aws-log-sample.json). Metrics use 60-second periods over the demonstration window; they are not isolated measurements of each short load sample.

## Cleanup and limits

Terraform removed the project stack in two successful deletion batches, after correcting a missing task-definition deregistration permission. The local Terraform state was subsequently checked and contained no resource entries.

At 21:14:32 UTC, [AWS read checks](evidence/aws-cleanup-check.json) returned no CloudLift database, load balancer, or ECS cluster. The demo endpoint is no longer live. Saved evidence and source code are retained.

The three fallback cleanup schedules were verified enabled and correctly targeted before testing, but were removed by manual teardown before their scheduled time. Their execution was not tested. They are not a substitute for complete teardown.

Public ECR images and the CLI user's policies are outside the Terraform stack. Residual database snapshots, managed-secret removal, removal of the temporary provisioner grant, and delayed final billing require separate checks; the primary-resource check does not establish those outcomes.

## Fixes discovered during the demonstration

- Added security-group creation/rule permissions and `ec2:GetSecurityGroupsForVpc` to the network policy.
- Allowed `ecs:DeregisterTaskDefinition` on `*` for teardown.
- Set ECS deployment maximum/minimum percentages to 200/100 for replacement-before-stop behavior with AZ rebalancing.
- Corrected the Scheduler RDS payload field to `DbInstanceIdentifier`.
- Updated GitHub's OIDC subject to include immutable owner/repository IDs.
- Removed the ineffective service-name condition on the registry bearer-token action.

## Previously completed locally: September 17, 2026

The prior record reports a successful Docker build, nine integration checks, 100 successful local load requests (p50 2.17 ms, p95 11.05 ms), and recovery with retained data after stopping/restarting a disposable PostgreSQL container. These are local results and must not be presented as AWS measurements. Terraform formatting and validation also passed.
