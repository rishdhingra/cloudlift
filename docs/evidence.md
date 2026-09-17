# Verification record

## Completed locally (2026-09-17)

- Docker image built with Node 22, non-root runtime, verified RDS CA bundle included.
- Nine integration checks passed: basic response, database health, input validation, synthetic customer insertion, duplicate handling, listing and count.
- 100 health requests / 5 workers: 100 successes, 0 failures; local p50 2.17 ms, p95 11.05 ms. These are laptop/container results, **not AWS performance measurements**.
- Stopped the disposable PostgreSQL container: API returned HTTP 503.
- Restarted it: API recovered and the inserted record remained.
- Removed all disposable test containers and their volumes.
- Terraform formatting/validation passed. Preliminary plan is not an authorization check for AWS create APIs.

## Required live evidence — pending

1. Capture deployment timestamp, git commit, immutable image digest, Terraform plan and outputs (never passwords/state files).
2. Confirm two healthy ECS targets in different AZs and RDS Multi-AZ status; capture ALB target health.
3. Run synthetic integration tests and save their JSON result.
4. Run bounded load at one task, then two tasks, recording p50/p95/errors and CloudWatch CPU, memory, request rate. Restore two tasks. This is a manual scaling comparison, not autoscaling.
5. Stop exactly one CloudLift ECS task while probing `/health`; record failed requests and time until replacement is healthy. Verify the synthetic customer is still present.
6. Trigger RDS reboot with failover during low-rate probes; record actual outage/recovery and unchanged data. Expect a temporary disruption; do not claim zero downtime.
7. Run the GitHub deployment workflow, verify the new image digest is serving, and retain the workflow URL/artifact.
8. Export CloudWatch charts/log samples and record test conditions and limitations.
9. Run Terraform destroy for this isolated project and verify no project tasks, database, ALB, log groups, schedules or snapshots remain. Check later billing for delayed usage.

Current blocker: `cloudlift-cli-user` is denied `rds:DescribeDBInstances`, `ecs:ListClusters`, and `iam:GetRole`. No paid application resources have been deployed by this work.
