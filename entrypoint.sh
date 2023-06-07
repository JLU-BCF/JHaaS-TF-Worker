#!/bin/sh

# Check env from backend presence
if [ -z "$JH_ACTION" ] \
|| [ -z "$JH_ID" ] \
|| [ -z "$JH_NAME" ] \
|| [ -z "$JH_STATUS" ] \
|| [ -z "$JH_SLUG" ] \
|| [ -z "$JH_GROUP_ID" ] \
|| [ -z "$JH_IMAGE" ] \
|| [ -z "$JH_INSTANCE_FLAVOUR" ] \
|| [ -z "$JH_INSTANCE_COUNT" ] \
|| [ -z "$JH_CONTACT" ]
then
  echo "Missing Config from JHaaS Backend! Exiting with failure code..." >&2
  exit 1
fi

# Check env from configmap presence
if [ -z "$JHAAS_DOMAIN" ] \
|| [ -z "$JHAAS_ISSUER" ] \
|| [ -z "$JHAAS_AUTHENTIK_URL" ] \
|| [ -z "$JHAAS_AUTHENTIK_TOKEN" ] \
|| [ -z "$JHAAS_AUTHENTICATION_FLOW" ] \
|| [ -z "$JHAAS_AUTHORIZATION_FLOW" ]
then
  echo "Missing Config from ConfigMap! Exiting with failure code..." >&2
  exit 2
fi

# Check secret presence
SECRETS_PATH="${SECRETS_PATH:-/secrets}"
S3_CONF="${S3_CONF:-minio.secret}"
KUBECONFIG="${KUBECONFIG:-kubeconfig.secret}"
if ! ([ -f "$SECRETS_PATH/$S3_CONF" ] && [ -f "$SECRETS_PATH/$KUBECONFIG" ]); then
  echo "Secrets are not configured properly! Exiting with failure code..." >&2
  exit 3
fi

# Setup TF Variables
export TF_VAR_kubeconfig="$SECRETS_PATH/$KUBECONFIG"
export TF_VAR_domain="$JHAAS_DOMAIN"
export TF_VAR_issuer="$JHAAS_ISSUER"
export TF_VAR_authentik_url="$JHAAS_AUTHENTIK_URL"
export TF_VAR_authentik_token="$JHAAS_AUTHENTIK_TOKEN"
export TF_VAR_authentik_jh_group_id="$JH_GROUP_ID"
export TF_VAR_authentication_flow="$JHAAS_AUTHENTICATION_FLOW"
export TF_VAR_authorization_flow="$JHAAS_AUTHORIZATION_FLOW"
export TF_VAR_name="$JH_SLUG"
export TF_VAR_jh_display_name="$JH_NAME"
export TF_VAR_oidc_id="$JH_ID"
export TF_VAR_jupyter_notebook_image="$JH_IMAGE"

if [ ! -z "$JH_DESC" ]; then
  export TF_VAR_jh_description="$JH_DESC"
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
  exit 4

fi

# Upload terraform state and logs
while true; do
  mc -C /root/.mc cp --recursive "$S3_PERSIST/" "$S3_PATH/$JH_ID/" && break
  echo "Could not save state! Try again in 5 min..."
  sleep 300
done
