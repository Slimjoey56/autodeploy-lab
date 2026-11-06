#!/usr/bin/env bash
set -euo pipefail

# Run once from AWS CloudShell or a machine with AWS CLI v2 and jq configured.
# This creates the GitHub OIDC role, ECS service roles, and ECR repository.

GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-Slimjoey56/autodeploy-lab}"
AWS_REGION="${AWS_REGION:-eu-west-1}"
DEPLOY_ROLE_NAME="GitHubActionsAutoDeployLabRole"
EXECUTION_ROLE_NAME="ecsTaskExecutionRole"
INFRASTRUCTURE_ROLE_NAME="ecsInfrastructureRoleForExpressServices"
ECR_REPOSITORY="autodeploy-lab"

command -v aws >/dev/null || { echo "AWS CLI is required." >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required." >&2; exit 1; }

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
PARTITION="$(aws sts get-caller-identity --query Arn --output text | cut -d: -f2)"

DEFAULT_VPC="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
  --region "$AWS_REGION" --query 'Vpcs[0].VpcId' --output text)"
if [[ -z "$DEFAULT_VPC" || "$DEFAULT_VPC" == "None" ]]; then
  echo "No default VPC exists in $AWS_REGION. Create a default VPC with public subnets before running this script." >&2
  exit 1
fi

PUBLIC_SUBNET_COUNT="$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC" \
  --region "$AWS_REGION" --query 'length(Subnets)' --output text)"
if (( PUBLIC_SUBNET_COUNT < 2 )); then
  echo "The default VPC in $AWS_REGION needs at least two subnets for the public load balancer." >&2
  exit 1
fi
OIDC_URL="token.actions.githubusercontent.com"
OIDC_ARN=""

while IFS= read -r provider_arn; do
  [[ -z "$provider_arn" ]] && continue
  provider_url="$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$provider_arn" --query Url --output text 2>/dev/null || true)"
  if [[ "$provider_url" == "$OIDC_URL" ]]; then
    OIDC_ARN="$provider_arn"
    break
  fi
done < <(aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text | tr '\t' '\n')

if [[ -z "$OIDC_ARN" ]]; then
  echo "Creating GitHub Actions OIDC provider..."
  OIDC_ARN="$(aws iam create-open-id-connect-provider \
    --url "https://$OIDC_URL" \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
    --query OpenIDConnectProviderArn --output text)"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/ecs-tasks-trust.json" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ecs-tasks.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
JSON

cat > "$TMP_DIR/ecs-infrastructure-trust.json" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ecs.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
JSON

cat > "$TMP_DIR/github-trust.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "$OIDC_ARN"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:$GITHUB_REPOSITORY:ref:refs/heads/main"
      }
    }
  }]
}
JSON

ensure_role() {
  local role_name="$1"
  local trust_file="$2"
  if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
    aws iam update-assume-role-policy --role-name "$role_name" --policy-document "file://$trust_file"
  else
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "file://$trust_file" >/dev/null
  fi
}

ensure_role "$EXECUTION_ROLE_NAME" "$TMP_DIR/ecs-tasks-trust.json"
aws iam attach-role-policy --role-name "$EXECUTION_ROLE_NAME" \
  --policy-arn "arn:$PARTITION:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"

ensure_role "$INFRASTRUCTURE_ROLE_NAME" "$TMP_DIR/ecs-infrastructure-trust.json"
aws iam attach-role-policy --role-name "$INFRASTRUCTURE_ROLE_NAME" \
  --policy-arn "arn:$PARTITION:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"

ensure_role "$DEPLOY_ROLE_NAME" "$TMP_DIR/github-trust.json"

ECR_ARN="arn:$PARTITION:ecr:$AWS_REGION:$ACCOUNT_ID:repository/$ECR_REPOSITORY"
cat > "$TMP_DIR/github-deploy-policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EcrLogin",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "PushApplicationImage",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart"
      ],
      "Resource": "$ECR_ARN"
    },
    {
      "Sid": "DeployExpressService",
      "Effect": "Allow",
      "Action": [
        "ecs:CreateCluster",
        "ecs:CreateExpressGatewayService",
        "ecs:DescribeClusters",
        "ecs:DescribeExpressGatewayService",
        "ecs:ListClusters",
        "ecs:ListServices",
        "ecs:RegisterTaskDefinition",
        "ecs:TagResource",
        "ecs:UpdateExpressGatewayService"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PassEcsServiceRoles",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:$PARTITION:iam::$ACCOUNT_ID:role/$EXECUTION_ROLE_NAME",
        "arn:$PARTITION:iam::$ACCOUNT_ID:role/$INFRASTRUCTURE_ROLE_NAME"
      ],
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": [
            "ecs.amazonaws.com",
            "ecs-tasks.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "CreateRequiredServiceLinkedRoles",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "iam:AWSServiceName": [
            "ecs.amazonaws.com",
            "elasticloadbalancing.amazonaws.com",
            "ecs.application-autoscaling.amazonaws.com"
          ]
        }
      }
    }
  ]
}
JSON

aws iam put-role-policy --role-name "$DEPLOY_ROLE_NAME" \
  --policy-name AutoDeployLabDeploymentPolicy \
  --policy-document "file://$TMP_DIR/github-deploy-policy.json"

if ! aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws ecr create-repository --repository-name "$ECR_REPOSITORY" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 \
    --region "$AWS_REGION" >/dev/null
fi

cat > "$TMP_DIR/ecr-lifecycle.json" <<'JSON'
{
  "rules": [{
    "rulePriority": 1,
    "description": "Keep the most recent 15 images",
    "selection": {
      "tagStatus": "any",
      "countType": "imageCountMoreThan",
      "countNumber": 15
    },
    "action": {"type": "expire"}
  }]
}
JSON

aws ecr put-lifecycle-policy --repository-name "$ECR_REPOSITORY" \
  --lifecycle-policy-text "file://$TMP_DIR/ecr-lifecycle.json" \
  --region "$AWS_REGION" >/dev/null


DEPLOY_ROLE_ARN="arn:$PARTITION:iam::$ACCOUNT_ID:role/$DEPLOY_ROLE_NAME"

echo
echo "AWS bootstrap complete."
echo "AWS_ACCOUNT_ID=$ACCOUNT_ID"
echo "AWS_REGION=$AWS_REGION"
echo "AWS_DEPLOY_ROLE_ARN=$DEPLOY_ROLE_ARN"
echo
echo "Add these GitHub repository variables:"
echo "  AWS_REGION=$AWS_REGION"
echo "  AWS_DEPLOY_ROLE_ARN=$DEPLOY_ROLE_ARN"
echo
echo "Repository: https://github.com/$GITHUB_REPOSITORY/settings/variables/actions"
echo "Allow up to a minute for new IAM roles to propagate before the first deployment."
