#!/bin/bash
set -e

REGION="us-east-1"
BUCKET_NAME="gin208-tfstate-ralph"
DYNAMO_TABLE="gin208-locks-ralph"

echo "=== Bootstrap Terraform Backend ==="

echo "[1/4] Bucket S3..."
aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION"

echo "[2/4] Versioning S3..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

echo "[3/4] Chiffrement + blocage acces public..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "[4/4] Table DynamoDB..."
aws dynamodb create-table \
  --table-name "$DYNAMO_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

echo "=== Bootstrap OK. Lance : terraform init ==="

