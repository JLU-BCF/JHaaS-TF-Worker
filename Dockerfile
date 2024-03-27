# MANDATORY
ARG ALPINE_TAG=latest

# Download prebuild binaries for tofu and s5cmd
FROM alpine:${ALPINE_TAG} as downloader

# MANDATORY
# Define tofu and s5cmd versions
ARG TOFU_VERSION
ARG S5CMD_VERSION

# Check if versions are set
RUN test -n "$TOFU_VERSION" && test -n "$S5CMD_VERSION"

# Download and extract tofu
RUN wget "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.zip" \
  && unzip "tofu_${TOFU_VERSION}_linux_amd64.zip" tofu

# Download and extract s5cmd
RUN wget "https://github.com/peak/s5cmd/releases/download/v${S5CMD_VERSION}/s5cmd_${S5CMD_VERSION}_Linux-64bit.tar.gz" \
  && tar -xzf "s5cmd_${S5CMD_VERSION}_Linux-64bit.tar.gz" s5cmd

# Copy and init terraform config
COPY tf-config jhaas-terraform-config
RUN ./tofu -chdir=jhaas-terraform-config init

###########

# Use alpine as small base image for production usage
FROM alpine:${ALPINE_TAG}

# Copy extracted binaries from previous stage
COPY --from=downloader /tofu /usr/bin/tofu
COPY --from=downloader /s5cmd /usr/bin/s5cmd

# Copy over terraform configuration
WORKDIR /root
COPY entrypoint.sh entrypoint.sh
COPY --from=downloader /jhaas-terraform-config jhaas-terraform-config

ENTRYPOINT ["/root/entrypoint.sh"]
