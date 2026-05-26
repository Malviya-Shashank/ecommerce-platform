#!/bin/bash
################################################################################
# Initial Setup Script
# Creates prerequisite AWS resources for Terraform backend
# State locking uses Terraform-native S3 lockfile (no DynamoDB needed)
################################################################################

set -euo pipefail

PROJECT_NAME="${1:-ecommerce}"
REGION="${2:-ap-south-1}"

echo "🚀 Setting up Terraform backend for ${PROJECT_NAME} in ${REGION}..."

# Create S3 bucket for Terraform state
echo "📦 Creating S3 bucket for Terraform state..."
aws s3api create-bucket \
    --bucket "${PROJECT_NAME}-platform-terraform-state" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}" 2>/dev/null || true

aws s3api put-bucket-versioning \
    --bucket "${PROJECT_NAME}-platform-terraform-state" \
    --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
    --bucket "${PROJECT_NAME}-platform-terraform-state" \
    --server-side-encryption-configuration '{
        "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
    }'

aws s3api put-public-access-block \
    --bucket "${PROJECT_NAME}-platform-terraform-state" \
    --public-access-block-configuration '{
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }'

echo "✅ Setup complete!"
echo ""
echo "ℹ️  State locking uses Terraform-native S3 lockfile (use_lockfile = true)"
echo "   No DynamoDB table is needed (requires Terraform >= 1.10)"
echo ""
echo "Next steps:"
echo "  1. cd terraform/environments/dev"
echo "  2. Update terraform.tfvars with your values"
echo "  3. terraform init"
echo "  4. terraform plan"
echo "  5. terraform apply"
