#!/bin/bash

MANDATORY_BACKEND_VARS='JH_ACTION JH_ID JH_NAME JH_STATUS JH_SLUG JH_GROUP_ID JH_IMAGE JH_INSTANCE_FLAVOUR JH_INSTANCE_COUNT JH_CONTACT JH_API_TOKEN'
MANDATORY_CONFIG_VARS='JHAAS_DOMAIN JHAAS_ISSUER JHAAS_AUTHENTIK_URL JHAAS_AUTHENTIK_TOKEN JHAAS_AUTHENTICATION_FLOW JHAAS_AUTHORIZATION_FLOW JHAAS_INVALIDATION_FLOW'
MANDATORY_MISSING=0

for ENVIRON in $MANDATORY_BACKEND_VARS ; do
  if [ -z "${!ENVIRON}" ]; then
    ((MANDATORY_MISSING++))
    echo "Mandatory variable $ENVIRON from Backend is missing!" >&2
  fi
done

for ENVIRON in $MANDATORY_CONFIG_VARS ; do
  if [ -z "${!ENVIRON}" ]; then
    ((MANDATORY_MISSING++))
    echo "Mandatory variable $ENVIRON from ConfigMap is missing!" >&2
  fi
done

if [ $MANDATORY_MISSING -gt 0 ] ; then
  echo "There are $MANDATORY_MISSING mandatory variables missing! Exiting with failure code..." >&2
  exit 1
fi

# Check secret presence
SECRETS_PATH="${SECRETS_PATH:-/secrets}"
S3_CONF="${S3_CONF:-s3.secret}"
KUBECONFIG="${KUBECONFIG:-kubeconfig.secret}"
if ! ([ -f "${SECRETS_PATH}/${S3_CONF}" ] && [ -f "${SECRETS_PATH}/${KUBECONFIG}" ]); then
  echo "Secrets are not configured properly! Exiting with failure code..." >&2
  exit 3
fi

# Setup TF Variables
export TF_VAR_kubeconfig="${SECRETS_PATH}/${KUBECONFIG}"
export TF_VAR_domain="${JHAAS_DOMAIN}"
export TF_VAR_issuer="${JHAAS_ISSUER}"
export TF_VAR_authentik_url="${JHAAS_AUTHENTIK_URL}"
export TF_VAR_authentik_token="${JHAAS_AUTHENTIK_TOKEN}"
export TF_VAR_authentik_jh_group_id="${JH_GROUP_ID}"
export TF_VAR_authentication_flow="${JHAAS_AUTHENTICATION_FLOW}"
export TF_VAR_authorization_flow="${JHAAS_AUTHORIZATION_FLOW}"
export TF_VAR_invalidation_flow="${JHAAS_INVALIDATION_FLOW}"
export TF_VAR_name="${JH_SLUG}"
export TF_VAR_jh_display_name="${JH_NAME}"
export TF_VAR_oidc_id="${JH_ID}"
export TF_VAR_jupyter_notebook_image="${JH_IMAGE}"
export TF_VAR_jh_api_token="${JH_API_TOKEN}"

declare -A OPTIONAL_TF_VAR_MAP
OPTIONAL_TF_VAR_MAP[JH_CHART_VERSION]="TF_VAR_jh_chart_version"
OPTIONAL_TF_VAR_MAP[JH_DESC]="TF_VAR_jh_description"
OPTIONAL_TF_VAR_MAP[JHAAS_ICON]="TF_VAR_jh_icon"
OPTIONAL_TF_VAR_MAP[JH_NB_DEFAULT_URL]="TF_VAR_jupyter_notebook_default_url"
OPTIONAL_TF_VAR_MAP[JH_ADMIN_ID]="TF_VAR_jh_admin_id"
OPTIONAL_TF_VAR_MAP[JH_PLACEHOLDER_REPLICAS]="TF_VAR_jh_placeholder_replicas"
OPTIONAL_TF_VAR_MAP[JH_CONCURRENT_SPAWN_LIMIT]="TF_VAR_jh_concurrent_spawn_limit"
OPTIONAL_TF_VAR_MAP[NB_START_TIMEOUT]="TF_VAR_nb_start_timeout"
OPTIONAL_TF_VAR_MAP[S3_DATA_SECRET_NAME]="TF_VAR_secret_name"
OPTIONAL_TF_VAR_MAP[S3_DATA_SECRET_NAMESPACE]="TF_VAR_secret_namespace"

for ENVIRON in "${!OPTIONAL_TF_VAR_MAP[@]}"; do
  if [ ! -z "${!ENVIRON}" ]; then
    export "${OPTIONAL_TF_VAR_MAP["$ENVIRON"]}"="${!ENVIRON}"
  fi
done

RESOURCE_MGMT_VARS='NB_RAM_GUARANTEE NB_CPU_GUARANTEE NB_RAM_LIMIT NB_CPU_LIMIT NB_COUNT_LIMIT NB_HOME_SIZE NB_HOME_MOUNT_PATH NS_RAM_LIMIT NS_CPU_LIMIT'
RESOURCE_MGMT_ENABLE=1

for ENVIRON in $RESOURCE_MGMT_VARS ; do
  if [ -z "${!ENVIRON}" ]; then
    RESOURCE_MGMT_ENABLE=0
    break
  fi
done

if [ $RESOURCE_MGMT_ENABLE -eq 1 ]; then
  for ENVIRON in $RESOURCE_MGMT_VARS ; do
    export "TF_VAR_${ENVIRON,,}"="${!ENVIRON}"
  done
fi

# Setup s3 sync folders
S3_CONF_PREFIX="${S3_CONF_PREFIX:-s3}"
S3_TF_STATE_BUCKET="${S3_TF_STATE_BUCKET:-tf-state}"
S3_JH_SPECS_BUCKET="${S3_JH_SPECS_BUCKET:-jh-specs}"
LOCAL_TF_STATE_DIR="${LOCAL_TF_STATE_DIR:-/root/tfstate}"
LOCAL_JH_SPECS_DIR="${LOCAL_JH_SPECS_DIR:-/root/jhspecs}"
S3_TF_STATE_PATH="${S3_CONF_PREFIX}:${S3_TF_STATE_BUCKET}/${JH_ID}"
S3_JH_SPECS_PATH="${S3_CONF_PREFIX}:${S3_JH_SPECS_BUCKET}/${JH_ID}"
JH_STATUS_FILE="${LOCAL_JH_SPECS_DIR}/JupyterHubRequestStatus"
JH_URL_FILE="${LOCAL_JH_SPECS_DIR}/JupyterHubUrl"

# Setup minio client config structure
export RCLONE_CONFIG="${SECRETS_PATH}/${S3_CONF}"
mkdir -p "${LOCAL_TF_STATE_DIR}"
mkdir -p "${LOCAL_JH_SPECS_DIR}"

# Create and/or sync bucket for jupyter hub
set -e
rclone mkdir "${S3_TF_STATE_PATH}"
rclone mkdir "${S3_JH_SPECS_PATH}"
rclone sync "${S3_TF_STATE_PATH}" "${LOCAL_TF_STATE_DIR}"
rclone sync "${S3_JH_SPECS_PATH}" "${LOCAL_JH_SPECS_DIR}"
set +e

env > "${LOCAL_TF_STATE_DIR}/env.dump"

# Run terraform stuff using openTofu
if [ "${JH_ACTION}" = "DEPLOY" ]; then

  # Create execution plan
  tofu -chdir="jhaas-terraform-config" plan \
    -state="${LOCAL_TF_STATE_DIR}/jh-deployment.tfstate" \
    -out="${LOCAL_TF_STATE_DIR}/jh-deployment.tfplan" \
    > "${LOCAL_TF_STATE_DIR}/jh-deployment.plan.log" \
    2> "${LOCAL_TF_STATE_DIR}/jh-deployment.plan.error.log"

  if [ "$?" = "0" ]; then
    # Apply execution plan
    tofu -chdir="jhaas-terraform-config" apply \
      -state="${LOCAL_TF_STATE_DIR}/jh-deployment.tfstate" \
      -state-out="${LOCAL_TF_STATE_DIR}/jh-deployment.tfstate" \
      -auto-approve \
      "${LOCAL_TF_STATE_DIR}/jh-deployment.tfplan" \
      > "${LOCAL_TF_STATE_DIR}/jh-deployment.deploy.log" \
      2> "${LOCAL_TF_STATE_DIR}/jh-deployment.deploy.error.log"

    if [ "$?" = "0" ]; then
      echo -n "DEPLOYED" > "${JH_STATUS_FILE}"
      echo -n "https://${JH_SLUG}.${JHAAS_DOMAIN}/" > "${JH_URL_FILE}"
    else
      echo -n "FAILED" > "${JH_STATUS_FILE}"
    fi
  else
    echo -n "FAILED" > "${JH_STATUS_FILE}"
  fi

elif [ "${JH_ACTION}" = "DEGRADE" ]; then

  # Apply execution plan
  tofu -chdir="jhaas-terraform-config" apply -destroy \
    -state="${LOCAL_TF_STATE_DIR}/jh-deployment.tfstate" \
    -state-out="${LOCAL_TF_STATE_DIR}/jh-deployment.tfstate" \
    -auto-approve \
    > "${LOCAL_TF_STATE_DIR}/jh-deployment.degrade.log" \
    2> "${LOCAL_TF_STATE_DIR}/jh-deployment.degrade.error.log"

  if [ "$?" = "0" ]; then
    echo -n "DEGRATED" > "${JH_STATUS_FILE}"
  else
    echo -n "FAILED" > "${JH_STATUS_FILE}"
  fi

else

  echo "Unknown action! Exiting with failure code..." >&2
  exit 4

fi

for logfile in "${LOCAL_TF_STATE_DIR}"/*.log; do
  echo '-----------------'
  echo '|'
  echo "| $logfile"
  echo '|'
  echo '-----------------'
  cat "$logfile"
done

# Upload tofu state and logs
while true; do
  rclone sync "${LOCAL_TF_STATE_DIR}" "${S3_TF_STATE_PATH}" && break
  echo "Could not save state! Try again in 5 min..."
  sleep 300
done

# Upload JupyterHubRequestStatus
while true; do
  rclone sync "${LOCAL_JH_SPECS_DIR}" "${S3_JH_SPECS_PATH}" && break
  echo "Could not save JupyterHubRequestStatus! Try again in 5 min..."
  sleep 300
done
