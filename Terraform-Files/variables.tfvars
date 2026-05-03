# ─────────────────────────────────────────
# TERRAFORM VARIABLE VALUES
#
# This file supplies actual values for all
# variables defined in variables.tf
#
# ⚠️  Add terraform.tfvars to .gitignore
#     if it contains sensitive values like
#     SSH keys or restricted CIDRs
# ─────────────────────────────────────────

# ── Project ───────────────────────────────
project_name = "todo-app"
environment  = "dev"

# ── AWS ───────────────────────────────────
aws_region = "us-east-2"

# ── EKS ───────────────────────────────────
eks_version        = "1.32"
node_instance_type = "t3.small"

# ── Jenkins EC2 ───────────────────────────
jenkins_instance_type = "m7i-flex.large"

# restrict SSH to your own IP for security
# find your IP at: https://checkip.amazonaws.com
# format: x.x.x.x/32
jenkins_ssh_cidr = "154.161.177.101/32"
