#!/bin/sh

# Check env from backend presence
if [ -z "${JH_ACTION}" ] \
|| [ -z "${JH_ID}" ] \
|| [ -z "${JH_NAME}" ] \
|| [ -z "${JH_STATUS}" ] \
|| [ -z "${JH_SLUG}" ] \
|| [ -z "${JH_GROUP_ID}" ] \
|| [ -z "${JH_IMAGE}" ] \
|| [ -z "${JH_INSTANCE_FLAVOUR}" ] \
|| [ -z "${JH_INSTANCE_COUNT}" ] \
|| [ -z "${JH_CONTACT}" ] \
|| [ -z "${JH_API_TOKEN}" ]
then
  echo "Missing Config from JHaaS Backend! Exiting with failure code..." >&2
  exit 1
fi

# Check env from configmap presence
if [ -z "${JHAAS_DOMAIN}" ] \
|| [ -z "${JHAAS_ISSUER}" ] \
|| [ -z "${JHAAS_AUTHENTIK_URL}" ] \
|| [ -z "${JHAAS_AUTHENTIK_TOKEN}" ] \
|| [ -z "${JHAAS_AUTHENTICATION_FLOW}" ] \
|| [ -z "${JHAAS_AUTHORIZATION_FLOW}" ]
then
  echo "Missing Config from ConfigMap! Exiting with failure code..." >&2
  exit 2
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
export TF_VAR_name="${JH_SLUG}"
export TF_VAR_jh_display_name="${JH_NAME}"
export TF_VAR_oidc_id="${JH_ID}"
export TF_VAR_jupyter_notebook_image="${JH_IMAGE}"
export TF_VAR_jh_api_token="${JH_API_TOKEN}"

if [ ! -z "${JH_CHART_VERSION}" ]; then
  export TF_VAR_jh_chart_version="${JH_CHART_VERSION}"
fi

if [ ! -z "${JH_DESC}" ]; then
  export TF_VAR_jh_description="${JH_DESC}"
fi

if [ ! -z "${JHAAS_ICON}" ]; then
  export TF_VAR_jh_icon="${JHAAS_ICON}"
fi

if [ ! -z "${JH_NB_DEFAULT_URL}" ]; then
  export TF_VAR_jupyter_notebook_default_url="${JH_NB_DEFAULT_URL}"
fi

if [ ! -z "${JH_ADMIN_ID}" ]; then
  export TF_VAR_jh_admin_id="${JH_ADMIN_ID}"
fi

if [ ! -z "${NB_RAM_GUARANTEE}" ] \
&& [ ! -z "${NB_CPU_GUARANTEE}" ] \
&& [ ! -z "${NB_RAM_LIMIT}" ] \
&& [ ! -z "${NB_CPU_LIMIT}" ] \
&& [ ! -z "${NB_COUNT_LIMIT}" ] \
&& [ ! -z "${NB_HOME_SIZE}" ] \
&& [ ! -z "${NB_HOME_MOUNT_PATH}" ] \
&& [ ! -z "${NS_RAM_LIMIT}" ] \
&& [ ! -z "${NS_CPU_LIMIT}" ]
then
  export TF_VAR_nb_ram_guarantee="${NB_RAM_GUARANTEE}"
  export TF_VAR_nb_cpu_guarantee="${NB_CPU_GUARANTEE}"
  export TF_VAR_nb_ram_limit="${NB_RAM_LIMIT}"
  export TF_VAR_nb_cpu_limit="${NB_CPU_LIMIT}"
  export TF_VAR_nb_count_limit="${NB_COUNT_LIMIT}"
  export TF_VAR_nb_home_size="${NB_HOME_SIZE}"
  export TF_VAR_nb_home_mount_path="${NB_HOME_MOUNT_PATH}"
  export TF_VAR_ns_ram_limit="${NS_RAM_LIMIT}"
  export TF_VAR_ns_cpu_limit="${NS_CPU_LIMIT}"
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

# Run terraform stuff
if [ "${JH_ACTION}" = "DEPLOY" ]; then

  # Create execution plan
  terraform -chdir="jhaas-terraform-config" plan \
    -state="${LOCAL_TF_STATE_DIR}/jh-deployment.tfstate" \
    -out="${LOCAL_TF_STATE_DIR}/jh-deployment.tfplan" \
    > "${LOCAL_TF_STATE_DIR}/jh-deployment.plan.log" \
    2> "${LOCAL_TF_STATE_DIR}/jh-deployment.plan.error.log"

  if [ "$?" = "0" ]; then
    # Apply execution plan
    terraform -chdir="jhaas-terraform-config" apply \
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
  terraform -chdir="jhaas-terraform-config" apply -destroy \
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

# Upload terraform state and logs
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
