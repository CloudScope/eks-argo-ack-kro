# GitHub Actions - Terraform Deployment Setup Guide

## Overview

This GitHub Actions workflow automates the deployment of Terraform infrastructure for the EKS VPC setup.

## Workflow Features

✅ **Automatic Plan on Pull Requests**
- Runs `terraform plan` on PR creation
- Posts plan summary as PR comment
- Validates Terraform format and configuration

✅ **Automatic Apply on Merge**
- Runs `terraform apply` when code is merged to main/master
- Requires environment approval for safety
- Uploads outputs as artifacts

✅ **Security**
- Uses AWS OIDC (OpenID Connect) for credential-free authentication
- No hardcoded AWS credentials in code
- Environment-based approval gates

✅ **Notifications**
- Slack notifications on success/failure
- Job summaries with commit and author info

✅ **Artifact Management**
- Stores Terraform plan files
- Exports outputs for reference

## Prerequisites

### 1. AWS OIDC Configuration

Set up AWS OIDC trust relationship with GitHub:

```bash
# Create IAM role with trust policy for GitHub
aws iam create-role --role-name github-terraform-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
          },
          "StringLike": {
            "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
          }
        }
      }
    ]
  }'

# Attach Terraform/VPC permissions policy
aws iam attach-role-policy --role-name github-terraform-role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

### 2. GitHub Secrets Configuration

Add the following secrets to your GitHub repository:

**Settings → Secrets and variables → Actions**

```
AWS_ROLE_TO_ASSUME
├── Value: arn:aws:iam::ACCOUNT_ID:role/github-terraform-role
│   (Replace ACCOUNT_ID with your AWS account ID)

SLACK_WEBHOOK (Optional)
├── Value: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
│   (Get from Slack App settings if you want notifications)
```

### 3. GitHub Environments (Recommended)

**Settings → Environments → Create "production"**

Add approval reviewers for production deployments to ensure safety.

## Workflow Triggers

| Event | Trigger | Behavior |
|-------|---------|----------|
| **Pull Request** | PR to main/master/develop | Runs plan, posts comment |
| **Push** | Merge to main/master | Runs plan + auto-apply |
| **Manual** | Workflow dispatch | Can run destroy dry-run |

### File Path Triggers

Workflow only runs when these paths change:
- `terraform/**` - Any Terraform files
- `.github/workflows/terraform-deploy.yml` - Workflow file itself

## Usage

### 1. Plan Changes (On Pull Request)

```bash
# Create a branch with your changes
git checkout -b feature/vpc-updates
# Make changes to terraform/*.tf files
git push origin feature/vpc-updates
```

**Result:**
- ✅ Terraform plan executes
- ✅ Plan summary posted as PR comment
- ✅ Format validation runs
- ✅ Artifacts uploaded

### 2. Apply Changes (On Merge)

```bash
# Merge PR to main
git checkout main
git merge feature/vpc-updates
git push origin main
```

**Result:**
- ✅ Final plan generated
- ✅ Plan artifact downloaded
- ✅ Terraform apply executes
- ✅ Outputs saved as artifact
- ✅ Slack notification sent

### 3. Manual Destroy Dry-Run

Use GitHub Actions UI:
- Go to **Actions** → **Terraform Deployment**
- Click **Run workflow** button
- Select **terraform-destroy-dry-run** job

**Result:**
- ✅ Shows what would be destroyed
- ⚠️ Does NOT destroy resources

## Environment Variables

Customize behavior in the workflow file:

```yaml
env:
  AWS_DEFAULT_REGION: us-east-1      # Change your region
  TF_VERSION: 1.5.0                  # Update Terraform version
```

## Monitoring

### View Workflow Runs

**GitHub UI Path:** Repository → Actions → Terraform Deployment

### Check Job Logs

1. Click on workflow run
2. Select job (terraform-plan or terraform-apply)
3. View step logs

### Download Artifacts

1. Workflow run → Artifacts
2. Download `tfplan` or `terraform-outputs`

## Troubleshooting

### Issue: "AWS credentials not found"

**Solution:**
- Verify AWS_ROLE_TO_ASSUME secret is set correctly
- Check OIDC provider configuration in AWS IAM
- Ensure role trust policy includes your repository

### Issue: "Plan shows unexpected changes"

**Solution:**
- Review PR comment with plan details
- Check `terraform.tfvars` for variable changes
- Verify AWS region settings

### Issue: "Slack notifications not received"

**Solution:**
- Verify SLACK_WEBHOOK secret is set
- Test webhook URL with curl:
  ```bash
  curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"Test"}' \
    YOUR_WEBHOOK_URL
  ```

### Issue: "Apply step skipped"

**Solution:**
- Ensure you're merging to main or master branch
- Check branch protection rules
- Verify environment approvals (if configured)

## Permissions Required

The GitHub role needs these AWS permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "iam:PassRole",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

For production, restrict to specific resources:
```json
{
  "Effect": "Allow",
  "Action": [
    "ec2:CreateVpc",
    "ec2:CreateSubnet",
    "ec2:CreateRouteTable",
    "ec2:CreateInternetGateway",
    "ec2:CreateNatGateway",
    "ec2:AllocateAddress",
    "ec2:DescribeVpcs",
    "ec2:DescribeSubnets",
    "ec2:DescribeRouteTables",
    "ec2:DescribeAvailabilityZones",
    "ec2:DescribeInternetGateways",
    "ec2:DescribeNatGateways",
    "ec2:DescribeAddresses",
    "ec2:DeleteVpc"
  ],
  "Resource": "*"
}
```

## Best Practices

1. ✅ **Always review PR plans before merging**
2. ✅ **Enable environment approval for production**
3. ✅ **Keep Terraform version pinned** (TF_VERSION env var)
4. ✅ **Monitor Slack notifications** for deployment status
5. ✅ **Use descriptive commit messages** for audit trails
6. ✅ **Test changes in a branch first** before merging
7. ✅ **Regularly review workflow logs** for issues
8. ✅ **Use AWS OIDC instead of static credentials**

## Workflow Diagram

```
PR Created
    ↓
terraform-plan job
    ├─ fmt check
    ├─ init
    ├─ validate
    ├─ plan
    └─ comment on PR
    ↓
Code Review
    ↓
Merge to main/master
    ↓
terraform-apply job
    ├─ download plan
    ├─ apply
    ├─ capture outputs
    └─ Slack notification
```

## Next Steps

1. Set up AWS OIDC provider (if not already done)
2. Add GitHub secrets (AWS_ROLE_TO_ASSUME, SLACK_WEBHOOK)
3. Push changes to a branch and create PR
4. Review plan in PR comment
5. Merge to main to trigger deployment

## Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS OIDC with GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Terraform GitHub Actions](https://registry.terraform.io/modules/hashicorp/setup-terraform/latest)
- [AWS Terraform Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
