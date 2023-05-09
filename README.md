# JHaaS Terraform Worker

This Repository contains the build files for the Terraform worker.

The Terraform Workers purpose is to be spawned when a JH should be deployed. It will get the details for the deployment injected (env or file based) and will then apply the [Terraform configuration](https://git.computational.bio.uni-giessen.de/it/jhaas). Afterwards it stores its state, other status information and mandatory secrets into a s3 bucket.

## WIP Notice

For getting started, this Image will only mock the TF stuff. It just receives the input, wait some time and stores fake information to s3.
