# One-session AWS demo runbook

## Before creating paid resources

1. Review `provisioner-policy.json`. An account administrator must create a temporary customer-managed policy from it and attach it to `cloudlift-cli-user`. It adds project-prefixed ECS/RDS/ALB/logging/scheduler/IAM permissions to the existing network/ECR permissions. Read/list and ECS task registration APIs require some `Resource: "*"` statements. Creating role policies is privileged; remove this temporary grant after teardown. It is not a sandbox or a dollar cap.
2. Confirm the active credits' applicable services include Fargate/ECS, RDS, ELB, VPC/public IPv4, CloudWatch, Secrets Manager and EventBridge Scheduler. The September 18 session showed $139.98 in credits and eligible listings for the main services. Recheck the balance, expiration and eligibility for each new session; historical credits are not a price guarantee.
3. Verify a gross-usage budget that excludes credits/refunds and has an email recipient. The September 18 session used a $5 monthly budget with actual-cost alerts at $4.25 and $5, plus a $5 forecast alert. Alerts lag and do not stop spending.
4. Check for an existing GitHub OIDC provider (`aws iam list-open-id-connect-providers --profile cloudlift`). Reuse it using the prepare script option; do not delete a shared provider during teardown.
5. Build/push the **updated** container for `linux/amd64`. The previous ECR image lacks the new TLS/IAM/migration code and must not be deployed with this configuration.

```sh
export AWS_PROFILE=cloudlift AWS_REGION=us-east-1
export ECR_URI=public.ecr.aws/c5t6h8t1/cloudlift-api
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws
docker build --platform linux/amd64 -t "${ECR_URI}:resume-demo" app
docker push "${ECR_URI}:resume-demo"
aws ecr-public describe-images --repository-name cloudlift-api --image-ids imageTag=resume-demo --query 'imageDetails[0].imageDigest' --output text
```

Use the returned digest and your current public IPv4 address:

```sh
python3 scripts/prepare_demo.py --image 'public.ecr.aws/c5t6h8t1/cloudlift-api@sha256:REPLACE' --client-ip YOUR_PUBLIC_IPV4
cd terraform
terraform fmt -check
terraform validate
terraform plan -out=demo.tfplan
```

The prepare script creates ignored local inputs, restricts ingress to your `/32`, starts with zero API tasks, and schedules cleanup four hours from preparation. Prepare a fresh deadline immediately before deployment. Confirm it is 2–6 hours in the future; never apply an old plan. Inspect for unwanted resources or replacement of existing resources.

## Deploy and initialize

`terraform apply demo.tfplan` starts billable resources. If any apply fails, clean up the partial deployment immediately rather than leaving it running. The cleanup schedules may not yet exist after a failed apply.

After apply, verify all three `cloudlift-cleanup-*` schedules are ENABLED at the expected UTC time and target only this project's resources. Record their settings. They have not been runtime-tested yet.

```sh
cd ..
python3 scripts/migrate.py
```

Only after migration succeeds, change `desired_count` in `terraform/demo.auto.tfvars.json` to `2`, plan and apply. Check that both targets are healthy in different AZs. Keep the desired count at two or fewer. Deployment maximum/minimum percentages are 200/100, so a two-task service can temporarily run up to four tasks during replacement. Inspect `terraform output -json demo` for the URL and identifiers.

Run the integration and load scripts against the demo URL and follow `evidence.md`. Keep tests below 300 requests and ten workers per run. Do not expose real customer data or broaden the ingress CIDR to the world.

## GitHub Actions

Publish reviewed code to `main`. Set repository variable `AWS_DEPLOY_ROLE_ARN` from Terraform's `github_deploy_role` output and `DEMO_EXPIRES_AT` to the cleanup timestamp. Trigger `Deploy existing demo`; it requires at least 20 minutes remaining and a running service. CI runs separately on push/PR.

The deployment role can publish the project's image and update the project's ECS service; it has no Terraform infrastructure creation or database-secret access. After a workflow run, record the deployed digest and update local `container_image` before any non-destroy Terraform apply to avoid reverting the image. The September 18 deployment run succeeded; see `evidence.md`. A new session still requires new variable values and verification.

## End the session

Save screenshots/video and sanitized results first. Then from `terraform/`:

```sh
terraform plan -destroy -out=cleanup.tfplan
terraform apply cleanup.tfplan
terraform state list
```

This project state includes the original networking, so full destroy also removes its VPC/subnets. It does not remove the separately created public ECR repository. Preserve source code and evidence; destroy only this named demo stack, never unrelated AWS resources.

Verify through AWS read/list APIs: no CloudLift ECS tasks/services, RDS database or retained automated/manual snapshots, ALB, log groups, or cleanup schedules. A database in `deleting` status is not yet fully gone. RDS-managed secrets should be removed with the database; verify rather than assume. Public ECR images remain separate and can be cleaned up after capturing the digest. Remove the temporary provisioner policy grant last.

The scheduled fallback stops the largest charges but leaves such things as logs, target groups, roles and schedules. It does not replace full cleanup, cannot guarantee $0, and must not be relied on before its creation is verified. Recheck delayed billing later.

## Provisioning permissions and portability

The provisioner policy supplements existing networking and ECR access; it is not a complete bootstrap policy. The actual network policy must allow security-group creation, deletion, ingress/egress authorization and revocation, plus `ec2:GetSecurityGroupsForVpc`. Scope creation to the selected project VPC and security groups, and scope group management to that VPC. A policy referencing the deleted September 18 VPC must be updated before a future deployment. Existing broad network permissions are not a claim of production least privilege.

`ecs:DeregisterTaskDefinition` requires the wildcard resource permission used by the tested provisioner policy. Terraform planning does not prove that AWS create/delete APIs are authorized.

The GitHub trust subject currently targets the verified IDs of `rishdhingra/cloudlift` and its `main` branch. Forks or a different owner/repository must use their own subject. See [GitHub's immutable subject documentation](https://docs.github.com/en/actions/reference/security/oidc). The registry bearer-token permission follows the unconditional single-action pattern in AWS's ECR Public managed policy; image writes remain scoped to the project repository.

Open a new Terminal tab with explicit `AWS_PROFILE=cloudlift` and `AWS_REGION=us-east-1`; a tab using the default MediBill identity will produce unrelated permission errors. After a partial apply or a policy change, regenerate the plan instead of reusing a stale one.

In `cleanup.tf`, EventBridge Scheduler's RDS universal-target input uses `DbInstanceIdentifier` (case-sensitive). All three schedules were created and inspected during the demonstration, but their timed execution was not exercised because manual teardown happened first.
