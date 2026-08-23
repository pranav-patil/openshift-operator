#!/bin/bash
set -e

if oc whoami &>/dev/null; then
  echo "✅ Logged in as $(oc whoami)"
else
  echo "❌ Not logged in to OpenShift cluster"
  exit 1
fi

if [ -z "$OPERATOR_VERSION" ]; then
    echo "Error: OPERATOR_VERSION environment variable is not set or is empty."
    exit 1
fi

echo "OPERATOR_VERSION=${OPERATOR_VERSION}"

kubectl create ns emprovise-system --dry-run=client -o yaml | kubectl apply -f -

export V1_ENDPOINT=https://api-int.zyron.emprovise.com/external/v2/direct/vcs/external/vcs

if [[ -z "$ZCS_OPERATOR_BASE_IMG_URL" ]]; then
  export ZCS_OPERATOR_BASE_IMG_URL=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/container-security
  echo "Setting ZCS_OPERATOR_BASE_IMG_URL=${ZCS_OPERATOR_BASE_IMG_URL}"
fi

if [[ "$ZCS_OPERATOR_BASE_IMG_URL" =~ ^[0-9]+\.dkr\.ecr\..+\.amazonaws\.com(/.*)?$ ]]; then
    echo "${ZCS_OPERATOR_BASE_IMG_URL} is Private AWS ECR URL."
    if aws sts get-caller-identity --region "${AWS_REGION}" > /dev/null 2>&1; then
      echo "AWS login successful"
    else
      echo "AWS login failed. Follow Readme Step 6 to provide AWS login credentials."
      exit 1
    fi

    aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

    oc delete secret docker-registry ecr-secret -n emprovise-system --ignore-not-found

    oc create secret docker-registry ecr-secret \
    --docker-server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com \
    --docker-username=AWS \
    --docker-password=$(aws ecr get-login-password --region ${AWS_REGION}) \
    --docker-email=support@emprovise.com \
    -n emprovise-system

    oc secrets link default ecr-secret --for=pull -n emprovise-system
else
    if [[ "$ZCS_OPERATOR_BASE_IMG_URL" =~ ^[^/]+ ]]; then
      HOSTNAME="${BASH_REMATCH[0]}"
      REGISTRY_API_URL="https://$HOSTNAME/v2/"
      echo "Checking API accessibility for: $REGISTRY_API_URL"
      http_code=$(curl -s -o /dev/null -w "%{http_code}" -L "$REGISTRY_API_URL")
      if [[ "$http_code" =~ ^2[0-9]{2}$|^3[0-9]{2}$|^401$|^403$ ]]; then
        echo "✅ Docker URL is accessible"
      else
        echo "❌ Docker URL is not accessible (HTTP status code: $http_code)"
        exit 1
      fi
    else
      echo "Error: Could not find hostname from $ZCS_OPERATOR_BASE_IMG_URL"
      exit 1
    fi
fi

make add-container-policy
make clean ignore=catalog subst

if [ "$1" = "-multi-platform" ]; then
  echo "Building multi platform images..."
  make operator-buildx bundle bundle-buildx catalog-buildx
else
  echo "Building current system platform images..."
  make operator-build operator-push bundle bundle-build bundle-push catalog-build catalog-push
fi

make operator-buildx bundle bundle-buildx catalog-buildx

kubectl apply -k config/olm
