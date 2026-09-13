#!/bin/sh
# Builds the RP image with Cloud Build and deploys it to Cloud Run.
#
#   rp/deploy/gcp/deploy.sh <gcp-project> [region]
#
# The image is built by Cloud Build rather than on this machine: Cloud Run
# runs amd64, and a Mac would build arm64. Terraform describes what runs, not
# how it is built, so the build happens between two applies — the first makes
# the registry the image is pushed to, the second runs the image.
set -eu

project=${1:?usage: deploy.sh <gcp-project> [region]}
region=${2:-asia-northeast1}
here=$(cd "$(dirname "$0")" && pwd)
rp=$(cd "$here/../.." && pwd)

# Tag by commit, marked when what goes into the image has changes not yet
# committed, so what runs can always be traced to what was built.
tag=$(git -C "$rp" rev-parse --short HEAD)
[ -z "$(git -C "$rp" status --porcelain -- Dockerfile serve.py public)" ] || tag="$tag-dirty"
repository="$region-docker.pkg.dev/$project/siop/rp"

# Terraform manages the other APIs through these two, so they have to be on
# before it can do anything. It cannot switch on what it needs to switch
# things on.
gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com \
  --project "$project"

cd "$here"
terraform init -input=false
# The registry has to exist before anything can be pushed to it. The image
# here only fills the variable; this apply does not touch the service.
terraform apply -input=false \
  -var "project=$project" -var "region=$region" -var "image=$repository:$tag" \
  -target=google_project_service.apis \
  -target=google_artifact_registry_repository.rp
gcloud builds submit "$rp" --project "$project" --tag "$repository:$tag"

# Run the build by digest, not by tag. A tag can be pushed again — two builds
# of the same uncommitted change share one — and Terraform, seeing the same
# name, would leave the old revision serving. A digest names this build alone.
digest=$(gcloud artifacts docker images describe "$repository:$tag" \
  --project "$project" --format='value(image_summary.digest)')
image="$repository@$digest"

# Recorded beside the state, which Terraform reads on its own, so a later plan
# or destroy in this directory needs no arguments. Like the state, it stays on
# this machine (.gitignore).
cat > "$here/terraform.tfvars" <<VARS
project = "$project"
region  = "$region"
image   = "$image"
VARS
terraform apply -input=false
