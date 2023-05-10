#!/bin/sh

# Do nothing, just print out the environment and names of attached secrets
env
[ -d /run/secrets ] && ls /run/secrets || echo 'no secrets attached'
