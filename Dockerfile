# MANDATORY
ARG ALPINE_TAG=latest

# Download prebuild binaries for tofu and rclone
FROM alpine:${ALPINE_TAG} AS downloader

# Run stuff in root homedir
WORKDIR /root

# MANDATORY
# Define tofu and rclone versions
ARG TOFU_VERSION
ARG RCLONE_VERSION

# Check if versions are set
RUN test -n "$TOFU_VERSION" && test -n "$RCLONE_VERSION"

# Download and extract tofu
RUN wget "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.zip" \
  && unzip -j "tofu_${TOFU_VERSION}_linux_amd64.zip" "tofu"

# Download and extract rclone
RUN wget "https://github.com/rclone/rclone/releases/download/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-amd64.zip" \
  && unzip -j "rclone-v${RCLONE_VERSION}-linux-amd64.zip" "rclone-v${RCLONE_VERSION}-linux-amd64/rclone"

# Copy and init terraform config
COPY tf-config jhaas-terraform-config
RUN ./tofu -chdir=jhaas-terraform-config init

###########

# Use alpine as small base image for production usage
FROM alpine:${ALPINE_TAG}

# Run stuff in root homedir
WORKDIR /root

# Copy extracted binaries from previous stage
COPY --from=downloader /root/tofu /usr/bin/tofu
COPY --from=downloader /root/rclone /usr/bin/rclone

# Copy over terraform configuration
COPY entrypoint.sh entrypoint.sh
COPY --from=downloader /root/jhaas-terraform-config jhaas-terraform-config

ENTRYPOINT ["/root/entrypoint.sh"]
