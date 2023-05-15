#!/bin/sh

# Do nothing, just print out the environment and names and hashes of attached secrets
env

SECRETS_PATH="${SECRETS_PATH:-/secrets}"
S3_CONF="${S3_CONF:-minio.secret}"
TF_CONF="${TF_CONF:-terraform.secret}"

if [ -d "$SECRETS_PATH" ]; then
  echo "-----------"
  ls -l "$SECRETS_PATH"
  echo "-----------"
  for SECRET in "$SECRETS_PATH"/*; do
    sha256sum "$SECRET";
  done
  echo "-----------"
  mkdir -p /root/.mc && ln -s "$SECRETS_PATH/$S3_CONF" /root/.mc/config.json
  echo "it's me: $(hostname)" > demo.txt
  date >> demo.txt
  mc -C /root/.mc mv demo.txt s3/tf-state/
else
  echo "Directory $SECRETS_PATH does not exist or is not a directory"
fi
