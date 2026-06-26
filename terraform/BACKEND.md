# Terraform Backend Configuration

This configuration uses AWS S3 for Terraform state storage with **native S3 locking** via `use_lockfile`.

> **Note**: DynamoDB-based state locking has been **deprecated** by HashiCorp. This configuration uses the modern S3 native locking approach.

## Backend Setup

### Bucket Details
- **S3 Bucket**: `terraform-backend-bucket-085960855786`
- **State File Key**: `eks-vpc/terraform.tfstate`
- **Lock File**: `eks-vpc/terraform.tfstate.tflock`
- **Region**: `ap-southeast-1`
- **Encryption**: AES256 (server-side)
- **Versioning**: Enabled
- **Public Access**: Blocked

### State Locking (S3 Native)
- **Method**: S3 lockfile (`use_lockfile = true`)
- **Lock File Location**: Same S3 bucket with `.tflock` extension
- **Mechanism**: AWS S3 object locking via file creation/deletion
- **Advantage**: No additional infrastructure (no DynamoDB needed)

## Prerequisites

Before initializing Terraform, ensure:

1. **AWS Credentials Configured**
   ```bash
   aws configure
   # or use AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables
   ```

2. **S3 Bucket Exists**
   - The bucket `terraform-backend-bucket-085960855786` must exist
   - You have read/write permissions to the bucket
   - **Versioning MUST be enabled** (required for state recovery)

3. **Required IAM Permissions** (for S3 locking):
   - `s3:ListBucket` - List objects in bucket
   - `s3:GetObject` - Read state file and lock file
   - `s3:PutObject` - Write state file and lock file
   - `s3:DeleteObject` - Delete lock file (required for `use_lockfile`)

## Setup Instructions

Your S3 bucket is already created manually. Verify these configurations are in place:

### Verify Configuration

**Create S3 Bucket:**
```bash
aws s3api create-bucket \
  --bucket terraform-backend-bucket-085960855786 \
  --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1
```

**Enable Versioning (REQUIRED for state recovery):**
```bash
aws s3api put-bucket-versioning \
  --bucket terraform-backend-bucket-085960855786 \
  --versioning-configuration Status=Enabled
```

**Enable Encryption (AES256):**
```bash
aws s3api put-bucket-encryption \
  --bucket terraform-backend-bucket-085960855786 \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

**Block Public Access:**
```bash
aws s3api put-public-access-block \
  --bucket terraform-backend-bucket-085960855786 \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

## Initialize Terraform

After backend infrastructure is ready:

```bash
cd terraform/

# Initialize Terraform with backend
terraform init

# If you have existing local state, Terraform will ask to migrate:
# "Do you want to copy existing state to the new backend?"
# Answer: yes
```

## Verify Backend Configuration

```bash
# List Terraform state in S3
aws s3 ls s3://terraform-backend-bucket-085960855786/eks-vpc/

# Check bucket versioning status
aws s3api get-bucket-versioning \
  --bucket terraform-backend-bucket-085960855786
```

## State Locking Behavior (S3 Native)

When Terraform operations are running:
- Terraform creates a lock file: `eks-vpc/terraform.tfstate.tflock` in S3
- Lock file contains operation details and timestamps
- Other users cannot acquire a lock while one is active
- Lock is automatically released after operation completes
- Highly efficient - no external services needed

**View Active Locks:**
```bash
aws s3 ls s3://terraform-backend-bucket-085960855786/eks-vpc/ | grep tflock
```

**Force Unlock (Emergency Only):**
```bash
# If a lock is stuck, you can manually delete it
aws s3 rm s3://terraform-backend-bucket-085960855786/eks-vpc/terraform.tfstate.tflock
```

⚠️ **Warning**: Only use force unlock if you're absolutely certain no operations are running.

## Security Best Practices

✅ **Implemented:**
- S3 server-side encryption enabled (AES256)
- S3 versioning enabled for state recovery
- Public access blocked (Block Public Access enabled)
- Native S3 locking (no external dependencies)

✅ **Additional Recommendations:**
1. **Enable MFA Delete** on S3 bucket (requires bucket owner account)
2. **Use S3 Bucket Policies** to restrict access to specific IAM roles/users
3. **Enable CloudTrail logging** for audit trail of state file access
4. **Use IAM Roles** instead of long-lived access keys (for CI/CD especially)
5. **Enable S3 Access Logging** to monitor bucket access
6. **Use KMS encryption** instead of AES256 for sensitive environments
7. **Set lifecycle policies** to manage old state versions
8. **Enable S3 Object Lock** (premium feature, immutability guarantee)

**Example IAM Policy for Terraform Backend Access:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::terraform-backend-bucket-085960855786",
      "Condition": {
        "StringEquals": {
          "s3:prefix": "eks-vpc"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::terraform-backend-bucket-085960855786/eks-vpc/terraform.tfstate"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::terraform-backend-bucket-085960855786/eks-vpc/terraform.tfstate.tflock"
    }
  ]
}
```

## Troubleshooting

### "NoSuchBucket" Error
- The S3 bucket doesn't exist
- Run `setup-backend.sh` or create manually
- Verify bucket name and region

### "UnrecognizedClientException" Error
- AWS credentials not configured or expired
- Run `aws configure` to set credentials
- Check IAM permissions

### Lock File Issues
- Lock file stuck: Use `aws s3 rm s3://bucket/path/tflock` (use cautiously)
- Permission denied on lock file: Verify IAM permissions include `s3:DeleteObject` on lock file

### State Recovery (Versioning)
```bash
# List all versions of state file
aws s3api list-object-versions \
  --bucket terraform-backend-bucket-085960855786 \
  --prefix eks-vpc/terraform.tfstate

# Restore a previous version
aws s3api get-object \
  --bucket terraform-backend-bucket-085960855786 \
  --key eks-vpc/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.recovered
```

### State Migration Issues

If migrating from local state:
```bash
# Backup local state first
cp terraform.tfstate terraform.tfstate.backup

# Re-initialize with backend config
terraform init

# Terraform will prompt to migrate state
```

## Migration from Local State

If you have existing local state files:

```bash
cd terraform/

# Create a backup
cp terraform.tfstate terraform.tfstate.backup
cp terraform.tfstate.backup ../ # backup outside terraform dir

# Initialize with backend
terraform init

# When prompted "Do you want to copy existing state to the new backend?"
# Answer: yes

# Verify migration
terraform state list
terraform show
```

## Cost Estimation

**Typical Monthly Costs (per AWS pricing as of 2024):**
- S3 Storage: ~$0.02 (minimal for state files)
- S3 PUT/GET Requests: ~$0.15 (standard pricing tier)
- S3 DELETE Requests (lock file cleanup): ~$0.02 (minimal)
- **Total: ~$0.20/month** (very minimal - essentially free)

> **Note**: No additional charges for S3 native locking. DynamoDB charges eliminated by using `use_lockfile = true`

**Cost Comparison:**
- With S3 Native Locking: ~$0.20/month
- With DynamoDB (deprecated): ~$1.50/month
- **Savings: ~87% lower cost!**

## Additional Resources

- [Terraform S3 Backend Documentation (Latest)](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Terraform State Locking](https://developer.hashicorp.com/terraform/language/state/locking)
- [AWS S3 Versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/manage-versioning-examples.html)
- [AWS S3 Access Control](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-access-control.html)
- [AWS S3 Encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingServerSideEncryption.html)

## Migration from DynamoDB-based Locking

If you have an existing Terraform backend using DynamoDB, you can safely migrate to S3 native locking:

```bash
# 1. Update backend.tf to use use_lockfile = true instead of dynamodb_table
# 2. Re-initialize backend
cd terraform
terraform init

# 3. Terraform will detect the configuration change
# 4. Old DynamoDB locks can be safely removed (no longer used)
aws dynamodb delete-table --table-name terraform-locks --region ap-southeast-1
```

**Note**: S3 native locking is the modern recommended approach as of Terraform 1.7+
