variable "github_repository" {
  type    = string
  default = "rishdhingra/cloudlift"
}
variable "existing_github_oidc_provider_arn" {
  description = "Set if this account already has the GitHub OIDC provider; do not create a duplicate."
  type        = string
  default     = ""
}
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.existing_github_oidc_provider_arn == "" ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_iam_role" "github" {
  name = "${var.project_name}-github-deploy"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity",
    Principal = { Federated = var.existing_github_oidc_provider_arn != "" ? var.existing_github_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn },
    Condition = { StringEquals = {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub" = "repo:rishdhingra@15848595/cloudlift@1373467968:ref:refs/heads/main"
    } }
  }] })
}
resource "aws_iam_role_policy" "github" {
  role = aws_iam_role.github.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "ecr-public:GetAuthorizationToken", Resource = "*" },
    { Effect = "Allow", Action = "sts:GetServiceBearerToken", Resource = "*" },
    { Effect = "Allow", Action = ["ecr-public:BatchCheckLayerAvailability", "ecr-public:InitiateLayerUpload", "ecr-public:UploadLayerPart", "ecr-public:CompleteLayerUpload", "ecr-public:PutImage", "ecr-public:DescribeImages"], Resource = "arn:aws:ecr-public::${data.aws_caller_identity.current.account_id}:repository/cloudlift-api" },
    { Effect = "Allow", Action = ["ecs:DescribeServices", "ecs:UpdateService"], Resource = aws_ecs_service.api.id },
    { Effect = "Allow", Action = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"], Resource = "*" },
    { Effect = "Allow", Action = "iam:PassRole", Resource = [aws_iam_role.execution.arn, aws_iam_role.task.arn], Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } } }
  ] })
}
output "github_deploy_role" { value = aws_iam_role.github.arn }
