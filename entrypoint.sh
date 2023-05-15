#!/bin/sh

# Do nothing, just print out the environment and names and hashes of attached secrets
env

SECRETS_PATH="${SECRETS_PATH:-/secrets}"

if [ -d "$SECRETS_PATH" ]; then
  echo "-----------"
  ls -l "$SECRETS_PATH"
  echo "-----------"
  for SECRET in "$SECRETS_PATH"/*; do
    sha256sum "$SECRET";
  done
  echo "-----------"
else
  echo "Directory $SECRETS_PATH does not exist or is not a directory"
fi
