FROM alpine:3.17

WORKDIR /root

COPY entrypoint.sh entrypoint.sh
COPY jhaas jhaas-terraform-config

# Download Terraform
ADD https://releases.hashicorp.com/terraform/1.4.6/terraform_1.4.6_linux_amd64.zip terraform.zip

# Download Minio
ADD https://dl.min.io/client/mc/release/linux-amd64/mc /usr/bin/mc

# TF and Minio config json will be injected as secret
RUN apk upgrade --no-cache --purge \
  && mkdir .mc \
  && ln -fs /run/secrets/minio.secret /root/.mc/config.json \
  && ln -fs /run/secrets/terraform.secret /root/.terraformrc \
  && unzip terraform.zip -d /usr/bin \
  && rm -f terraform.zip \
  && chmod 755 entrypoint.sh \
  && chmod 755 /usr/bin/mc

# ENTRYPOINT ["/root/entrypoint.sh"]
