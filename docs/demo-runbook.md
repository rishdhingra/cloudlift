# One-session AWS demo runbook

## Before creating paid resources

1. Review `provisioner-policy.json`. An account administrator must create a temporary customer-managed policy from it and attach it to `cloudlift-cli-user`. It adds project-prefixed ECS/RDS/ALB/logging/scheduler/IAM permissions to the existing network/ECR permissions. Read/list and ECS task registration APIs require some `Resource: "*"` statements. Creating role policies is privileged; remove this temporary grant after teardown. It is not a sandbox or a dollar cap.
2. Confirm the active credits' applicable services include Fargate/ECS, RDS, ELB, VPC/public IPv4, CloudWatch, Secrets Manager and EventBridge Scheduler. The balance was shown as $139.98, but service applicability is not yet verified.
3. Configure billing alerts for gross usage (exclude credits) at $5 and $10 and a separate net-cost alert. Alerts lag and do not stop spending. Choose the notification email yourself.
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

Only after migration succeeds, change `desired_count` in `terraform/demo.auto.tfvars.json` to `2`, plan and apply. Check that both targets are healthy in different AZs. Do not increase beyond two tasks. Inspect `terraform output -json demo` for the URL and identifiers.

Run the integration and load scripts against the demo URL and follow `evidence.md`. Keep tests below 300 requests and ten workers per run. Do not expose real customer data or broaden the ingress CIDR to the world.

## GitHub Actions

Publish reviewed code to `main`. Set repository variable `AWS_DEPLOY_ROLE_ARN` from Terraform's `github_deploy_role` output and `DEMO_EXPIRES_AT` to the cleanup timestamp. Trigger `Deploy existing demo`; it requires at least 20 minutes remaining and a running service. CI runs separately on push/PR.

The deployment role can publish the project's image and update the project's ECS service; it has no Terraform infrastructure creation or database-secret access. After a workflow run, record the deployed digest and update local `container_image` before any non-destroy Terraform apply to avoid reverting the image. No AWS deployment workflow run has been completed yet.

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
