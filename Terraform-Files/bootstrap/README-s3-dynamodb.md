# Terraform Remote State Bootstrap

This module provisions the foundational AWS infrastructure required **before** any other Terraform project can use remote state. It creates an S3 bucket for storing `.tfstate` files and a DynamoDB table for state locking — preventing concurrent `terraform apply` runs from corrupting shared state.

---

## Why This Exists

Terraform state tracks every resource it manages. By default, state is stored locally in a `terraform.tfstate` file — which is fine for solo work, but breaks down in teams or CI/CD pipelines:

| Problem | Without Remote State | With This Module |
|---|---|---|
| Team collaboration | State conflicts, overwrites | Single source of truth in S3 |
| Concurrent runs | Corrupted state | DynamoDB lock prevents it |
| State history / rollback | No versioning | S3 versioning keeps full history |
| Accidental deletion | State file lost forever | `prevent_destroy` + versioning |
| Sensitive data in state | Plaintext on disk | AES-256 encryption at rest |

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Developer / CI                     │
│              runs: terraform apply                   │
└────────────────────┬────────────────────────────────┘
                     │
          ┌──────────▼──────────┐
          │   DynamoDB Table    │  ← Acquires lock before apply
          │  (tf_lock / LockID) │    Releases lock after apply
          └──────────┬──────────┘
                     │
          ┌──────────▼──────────┐
          │     S3 Bucket       │  ← Reads current state
          │  (tf_state / .tfstate) │  Writes updated state
          │  - Versioning ON    │
          │  - AES-256 SSE      │
          │  - Public access OFF│
          └─────────────────────┘
```

---

## File Structure

```
.
├── bootstrap/
├── provider.tf       # Terraform + AWS provider version constraints
├── variables.tf      # Configurable inputs (region, bucket name, table name)
├── s3.tf             # S3 bucket + versioning + encryption + public access block
├── dynamodb.tf       # DynamoDB table for state locking
└── outputs.tf        # Outputs consumed by other Terraform projects
```

---

## File Reference

### `provider.tf`

Declares the minimum Terraform CLI version and the AWS provider source/version:

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

- **`required_version >= 1.5.0`** — enforces a modern Terraform CLI. Older versions have known bugs around state handling.
- **`version = "~> 5.0"`** — allows any `5.x` patch/minor release but not `6.0`, preventing breaking changes.
- The region is driven by `var.aws_region` (default: `us-east-2`) so it stays configurable without editing provider code.

---

### `variables.tf`

```hcl
variable "aws_region" {
  default = "us-east-2"
}

variable "bucket_name" {
  default = "cloud-native-buckettt"
}

variable "dynamodb_table_name" {
  default = "cloud-native-dynamodb-lock"
}
```

| Variable | Default | Purpose |
|---|---|---|
| `aws_region` | `us-east-2` | AWS region for all resources |
| `bucket_name` | `cloud-native-buckettt` | S3 bucket name (globally unique) |
| `dynamodb_table_name` | `cloud-native-dynamodb-lock` | DynamoDB table name |

> **Note:** S3 bucket names are globally unique across all AWS accounts. If the default name is already taken, override it: `terraform apply -var='bucket_name=my-unique-bucket-xyz'`

---

### `dynamodb.tf`

```hcl
resource "aws_dynamodb_table" "tf_lock" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = var.dynamodb_table_name
    ManagedBy = "terraform"
  }
}
```

**Key decisions explained:**

- **`hash_key = "LockID"`** — Terraform's S3 backend hardcodes this attribute name when writing lock records. It must be exactly `LockID` (case-sensitive).
- **`type = "S"`** — The lock value is a string (the path to the state file being locked).
- **`billing_mode = "PAY_PER_REQUEST"`** — No capacity planning needed. Lock operations are infrequent; on-demand billing is cheaper than provisioned throughput for this workload.
- **`prevent_destroy = true`** — A lifecycle guard that causes `terraform destroy` (or any plan that would delete this table) to fail with an error. This protects against accidentally deleting the lock table while other projects depend on it.

---

### `s3.tf`

This file creates four separate resources that together configure a secure, production-ready state bucket.

#### 1. The bucket itself

```hcl
resource "aws_s3_bucket" "tf_state" {
  bucket = var.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}
```

- `prevent_destroy = true` — same protection as DynamoDB: prevents accidental deletion of the bucket containing all your state files.

#### 2. Versioning

```hcl
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

Every `terraform apply` writes a new version of the state file. With versioning enabled, S3 retains all previous versions, so you can:
- Inspect state at any point in time
- Manually restore a previous version if state becomes corrupted

#### 3. Server-side encryption

```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

Terraform state often contains sensitive values (passwords, private keys, connection strings). AES-256 (SSE-S3) encrypts every object at rest automatically, with no performance impact and no cost beyond standard S3 storage.

#### 4. Public access block

```hcl
resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
```

All four settings are enabled to ensure the state bucket can **never** be made public — even if someone accidentally sets a permissive bucket policy or ACL. This is the recommended hardening for any bucket that should remain private.

---

### `outputs.tf`

```hcl
output "bucket_name" {
  value = aws_s3_bucket.tf_state.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.tf_lock.name
}
```

These outputs surface the exact resource names after `terraform apply`. You'll copy these values into the `backend` block of every other Terraform project that uses this remote state.

---

## Usage

### Step 1 — Bootstrap (run once)

This module is intentionally **local-state only** — it cannot use remote state to manage itself, because the remote state infrastructure doesn't exist yet.

```bash
terraform init
terraform plan
terraform apply
```

After `apply`, note the outputs:

```
Outputs:

bucket_name         = "cloud-native-buckettt"
dynamodb_table_name = "cloud-native-dynamodb-lock"
```

### Step 2 — Configure remote state in other projects

In every other Terraform project, add a `backend` block referencing these resources:

```hcl
# In your other project's provider.tf or backend.tf
terraform {
  backend "s3" {
    bucket         = "cloud-native-buckettt"           # from output
    key            = "projects/my-app/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "cloud-native-dynamodb-lock"      # from output
    encrypt        = true
  }
}
```

Then run `terraform init` in that project — Terraform will migrate state to S3 and start using DynamoDB for locking automatically.

> **Tip:** Use a unique `key` path per project/environment, e.g. `env/prod/networking/terraform.tfstate`. This keeps state files isolated within the same bucket.

---

## Overriding Defaults

You can override any variable at apply time without modifying the code:

```bash
# Different region and bucket name
terraform apply \
  -var="aws_region=eu-west-1" \
  -var="bucket_name=my-company-tf-state-prod" \
  -var="dynamodb_table_name=my-company-tf-lock"
```

Or via a `.tfvars` file:

```hcl
# terraform.tfvars
aws_region          = "eu-west-1"
bucket_name         = "my-company-tf-state-prod"
dynamodb_table_name = "my-company-tf-lock"
```

```bash
terraform apply -var-file="terraform.tfvars"
```

---

## Requirements

| Tool | Version |
|---|---|
| Terraform CLI | >= 1.5.0 |
| AWS Provider | ~> 5.0 |
| AWS credentials | Must have permissions for S3 and DynamoDB |

**Minimum IAM permissions needed to run this module:**

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:CreateBucket",
    "s3:PutBucketVersioning",
    "s3:PutEncryptionConfiguration",
    "s3:PutBucketPublicAccessBlock",
    "dynamodb:CreateTable",
    "dynamodb:DescribeTable",
    "dynamodb:DeleteTable"
  ],
  "Resource": "*"
}
```

---

## Important Notes

- **Do not add a `backend` block to this module.** It must run with local state. Adding a remote backend here creates a chicken-and-egg problem.
- **Do not run `terraform destroy`** on this module while other projects are using the bucket and table. The `prevent_destroy` lifecycle rules will block it, but be aware of the dependency.
- **S3 bucket names are globally unique.** If `terraform apply` fails with a `BucketAlreadyExists` error, choose a different `bucket_name`.
- **State is sensitive.** Limit IAM access to the S3 bucket and DynamoDB table to only the identities (users, roles, CI pipelines) that run Terraform.
