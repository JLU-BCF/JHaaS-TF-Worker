#!/bin/sh

TF_DEFAULT_REGISTRY="app.terraform.io"
TF_SANITIZED_REGISTRY="$(echo -n ${TF_REGISTRY:-${TF_DEFAULT_REGISTRY}} | tr '.' '_')"
TF_CONF_DIR="tf-config"
mkdir -p "${TF_CONF_DIR}"

# Check TF Module to be loaded (e.g. JH Deployment)
if [ -z ${TF_MODULE} ]; then
  echo "Missing Terraform Module! Exiting with failure code..." >&2
  exit 5
fi

if [ -z ${TF_REGISTRY} ]; then
  echo "No registry for Terraform Module given. Assuming '${TF_DEFAULT_REGISTRY}'."
fi

if [ -z ${TF_ACCESS_TOKEN} ]; then
  echo "No access token for Terraform Module given. Assuming a public module."
  terraform -chdir="${TF_CONF_DIR}" init -from-module="${TF_MODULE}"
else
  env "TF_TOKEN_${TF_SANITIZED_REGISTRY}=${TF_ACCESS_TOKEN}" terraform init -from-module="${TF_MODULE}"
fi

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
|| [ -z "${JH_CONTACT}" ]
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
S3_CONF="${S3_CONF:-minio.secret}"
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

if [ ! -z "${JH_DESC}" ]; then
  export TF_VAR_jh_description="${JH_DESC}"
fi

if [ ! -z "${JHAAS_ICON}" ]; then
  export TF_VAR_jh_icon="${JHAAS_ICON}"
fi

if [ ! -z "${JH_NB_DEFAULT_URL}" ]; then
  export TF_VAR_jupyter_notebook_default_url="${JH_NB_DEFAULT_URL}"
fi

# Setup s3 sync folders
S3_CONF_PREFIX="${S3_CONF_PREFIX:-s3}"
S3_TF_STATE_BUCKET="${S3_TF_STATE_BUCKET:-tf-state}"
S3_JH_SPECS_BUCKET="${S3_JH_SPECS_BUCKET:-jh-specs}"
LOCAL_TF_STATE_DIR="${LOCAL_TF_STATE_DIR:-/root/tfstate}"
LOCAL_JH_SPECS_DIR="${LOCAL_JH_SPECS_DIR:-/root/jhspecs}"
S3_TF_STATE_PATH="${S3_CONF_PREFIX}/${S3_TF_STATE_BUCKET}/${JH_ID}"
S3_JH_SPECS_PATH="${S3_CONF_PREFIX}/${S3_JH_SPECS_BUCKET}/${JH_ID}"
JH_STATUS_FILE="${LOCAL_JH_SPECS_DIR}/JupyterHubRequestStatus"
JH_URL_FILE="${LOCAL_JH_SPECS_DIR}/JupyterHubUrl"

# Setup minio client config structure
mkdir -p /root/.mc && ln -s "${SECRETS_PATH}/${S3_CONF}" /root/.mc/config.json
mkdir -p "${LOCAL_TF_STATE_DIR}"
mkdir -p "${LOCAL_JH_SPECS_DIR}"

# Create and/or sync bucket for jupyter hub
set -e
mc -C /root/.mc mb "${S3_TF_STATE_PATH}"
mc -C /root/.mc mb "${S3_JH_SPECS_PATH}"
mc -C /root/.mc cp --recursive "${S3_TF_STATE_PATH}/" "${LOCAL_TF_STATE_DIR}/"
mc -C /root/.mc cp --recursive "${S3_JH_SPECS_PATH}/" "${LOCAL_JH_SPECS_DIR}/"
set +e

# Run terraform stuff
if [ "${JH_ACTION}" = "DEPLOY" ]; then

  # Create execution plan
  terraform -chdir="${TF_CONF_DIR}" plan \
    -state="${LOCAL_TF_STATE_DIR}/jh-deployment.tfstate" \
    -out="${LOCAL_TF_STATE_DIR}/jh-deployment.tfplan" \
    > "${LOCAL_TF_STATE_DIR}/jh-deployment.plan.log" \
    2> "${LOCAL_TF_STATE_DIR}/jh-deployment.plan.error.log"

  if [ "$?" = "0" ]; then
    # Apply execution plan
    terraform -chdir="${TF_CONF_DIR}" apply \
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
  terraform -chdir="${TF_CONF_DIR}" apply -destroy \
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

# Upload terraform state and logs
while true; do
  mc -C /root/.mc cp --recursive "${LOCAL_TF_STATE_DIR}/" "${S3_TF_STATE_PATH}/" && break
  echo "Could not save state! Try again in 5 min..."
  sleep 300
done

# Upload JupyterHubRequestStatus
while true; do
  mc -C /root/.mc cp --recursive "${LOCAL_JH_SPECS_DIR}/" "${S3_JH_SPECS_PATH}/" && break
  echo "Could not save JupyterHubRequestStatus! Try again in 5 min..."
  sleep 300
done
