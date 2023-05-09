# FROM alpine:3.17
FROM hashicorp/terraform:1.4

WORKDIR /root

COPY entrypoint.sh entrypoint.sh
RUN chmod 755 entrypoint.sh
COPY jhaas jhaas-terraform-config

# Add Terraform
# ADD https://releases.hashicorp.com/terraform/1.4.6/terraform_1.4.6_linux_amd64.zip terraform.zip
# RUN unzip terraform.zip -d /usr/bin && rm -f terraform.zip

# Add Minio
ADD https://dl.min.io/client/mc/release/linux-amd64/mc /usr/bin/mc
RUN chmod 755 /usr/bin/mc

# TF and Minio config json will be injected as secret
RUN mkdir .mc \
  && ln -fs /run/secrets/minio.secret /root/.mc/config.json \
  && ln -fs /run/secrets/terraform.secret /root/.terraformrc

# ENTRYPOINT ["/root/entrypoint.sh"]
