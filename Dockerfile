# Self-build binaries, as official distribution
# channels are enormously delayed regarding security patches
FROM golang:1.20-bullseye AS BUILDER

# define Terraform (TF) and Minio Client (MC) Versions
ARG TF_VERSION="v1.4.6"
ARG MC_VERSION="RELEASE.2023-05-04T18-10-16Z"

# Go compiler options
ENV GOOS=linux
ENV GOARCH=amd64
ENV CGO_ENABLED=0

# install terraform
RUN go install github.com/hashicorp/terraform@$TF_VERSION

# install mc
RUN go install github.com/minio/mc@$MC_VERSION

###########

# Use alpine as small base image for production usage
FROM alpine:3.17

# Upgrade base image packages
# TF and MC config files will be injected as secrets, symlink them
RUN apk upgrade --no-cache --purge

# Add git as it is needed for terraform init stuff
RUN apk add --no-cache git

# Copy self-built binaries from previous stage
COPY --from=BUILDER /go/bin/mc /usr/bin/mc
COPY --from=BUILDER /go/bin/terraform /usr/bin/terraform

# Copy entrypoint
WORKDIR /root
COPY entrypoint.sh entrypoint.sh


ENTRYPOINT ["/root/entrypoint.sh"]
