# Terraform AWS Provider Coding Instructions

## 1. Core Principles
* Target the latest stable version of Terraform (v1.14+) and the AWS Provider (v6.x+).
* Never use deprecated arguments or resources.
* Prioritize modern, secure, and cost-optimized infrastructure.

## 2. Resource Naming and Structure
* Use snake_case for all resource, variable, and output names.
* Resource local names must be descriptive and distinct (e.g., `aws_instance.web_server`, not `aws_instance.this`).
* Group resources logically: variables in `variables.tf`, providers in `providers.tf`, outputs in `outputs.tf`, and infrastructure in `main.tf`.

## 3. Mandatory Syntax & Modern Schema Rules
* Always use `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` resources instead of the deprecated inline `ingress` and `egress` blocks within `aws_security_group`.
* Always use `aws_s3_bucket_versioning`, `aws_s3_bucket_server_side_encryption_configuration`, and `aws_s3_bucket_public_access_block` instead of deprecated inline arguments within `aws_s3_bucket`.
* For IAM policies, use the `aws_iam_policy_document` data source. Do not hardcode JSON strings or use `jsonencode()` for complex policies.

## 4. Best Practices & Security
* Use `for_each` instead of `count` when creating multiple similar resources to prevent destructive indexing updates.
* Ensure all state-managed data complies with minimum security baselines (e.g., enable encryption at rest for S3 buckets, KMS keys, and EBS volumes).
* Include a standard `tags` block on all taggable AWS resources, utilizing the `default_tags` block at the provider level where applicable.
