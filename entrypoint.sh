#!/bin/sh

# Check env from backend presence
if [ -z $JH_ACTION ] \
|| [ -z $JH_ID ] \
|| [ -z $JH_STATUS ] \
|| [ -z $JH_SLUG ] \
|| [ -z $JH_IMAGE ] \
|| [ -z $JH_INSTANCE_FLAVOUR ] \
|| [ -z $JH_INSTANCE_COUNT ] \
|| [ -z $JH_DESC ] \
|| [ -z $JH_CONTACT ]
then
  echo "Missing Config from JHaaS Backend! Exiting with failure code..." >&2
  exit 1
fi

# Check secret presence
SECRETS_PATH="${SECRETS_PATH:-/secrets}"
S3_CONF="${S3_CONF:-minio.secret}"
KUBECONFIG="${KUBECONFIG:-kubeconfig.secret}"
if ! ([ -f "$SECRETS_PATH/$S3_CONF" ] && [ -f "$SECRETS_PATH/$KUBECONFIG" ]); then
  echo "Secrets are not configured properly! Exiting with failure code..." >&2
  exit 2
fi

# Setup s3 sync folders
S3_PERSIST=/root/tfstate
S3_PATH=s3/tf-state

# Setup minio client config structure
mkdir -p /root/.mc && ln -s "$SECRETS_PATH/$S3_CONF" /root/.mc/config.json
mkdir -p "$S3_PERSIST"

# Create and/or sync bucket for jupyter hub
set -e
mc -C /root/.mc mb "$S3_PATH/$JH_ID"
mc -C /root/.mc cp --recursive "$S3_PATH/$JH_ID/" "$S3_PERSIST/"
set +e

# Run terraform stuff
if [ "$JH_ACTION" = "DEPLOY" ]; then

  # Create execution plan
  terraform -chdir="jhaas-terraform-config" plan \
    -state="$S3_PERSIST/jh-deployment.tfstate" \
    -out="$S3_PERSIST/jh-deployment.tfplan" \
    > "$S3_PERSIST/jh-deployment.plan.log" \
    2> "$S3_PERSIST/jh-deployment.plan.error.log"

  # Apply execution plan
  terraform -chdir="jhaas-terraform-config" apply \
    -state="$S3_PERSIST/jh-deployment.tfstate" \
    -state-out="$S3_PERSIST/jh-deployment.tfstate" \
    -auto-approve \
    "$S3_PERSIST/jh-deployment.tfplan" \
    > "$S3_PERSIST/jh-deployment.deploy.log" \
    2> "$S3_PERSIST/jh-deployment.deploy.error.log"

elif [ "$JH_ACTION" = "DEGRADE" ]; then

  # Apply execution plan
  terraform -chdir="jhaas-terraform-config" apply -destroy \
    -state="$S3_PERSIST/jh-deployment.tfstate" \
    -state-out="$S3_PERSIST/jh-deployment.tfstate" \
    -auto-approve \
    > "$S3_PERSIST/jh-deployment.degrade.log" \
    2> "$S3_PERSIST/jh-deployment.degrade.error.log"

else

  echo "Unknown action! Exiting with failure code..." >&2
  exit 3

fi

# Upload terraform state and logs
while true; do
  mc -C /root/.mc cp --recursive "$S3_PERSIST/" "$S3_PATH/$JH_ID/" && break
  echo "Could not save state! Try again in 5 min..."
  sleep 300
done
