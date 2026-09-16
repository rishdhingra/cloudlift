variable "aws_region" {
  description = "AWS region for CloudLift"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for AWS resource tags"
  type        = string
  default     = "cloudlift"
}
