#!/usr/bin/env bash
# Create and publish a custom container image to a private registry (Junior KEY).
# Uses Amazon ECR (your aws CLI is already logged in). Region us-east-1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export AWS_PAGER=""
REGION="${REGION:-us-east-1}"
REPO="${REPO:-peex-app}"
TAG="${TAG:-1.0.0}"
LOCAL_IMAGE="${IMAGE:-peex-app:1.0.0}"

aws sts get-caller-identity >/dev/null || { echo "aws not logged in"; exit 1; }
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
TARGET="${REGISTRY}/${REPO}:${TAG}"

echo "== Ensure ECR repository exists =="
aws ecr describe-repositories --repository-names "$REPO" --region "$REGION" >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name "$REPO" --region "$REGION" \
       --image-scanning-configuration scanOnPush=true \
       --tags Key=Project,Value=PeEx Key=Competency,Value=containers >/dev/null
echo "repo: $REPO"

echo "== Log docker in to ECR =="
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

echo "== Tag and push =="
docker tag "$LOCAL_IMAGE" "$TARGET"
docker push "$TARGET"

echo "== Published image in ECR (proof) =="
aws ecr describe-images --repository-name "$REPO" --region "$REGION" \
  --query 'sort_by(imageDetails,&imagePushedAt)[-1].{Tags:imageTags,Digest:imageDigest,Pushed:imagePushedAt,SizeMB:imageSizeInBytes}' \
  --output table
echo "Pushed: $TARGET"
