#!/bin/sh
# Builds the RP image with Cloud Build and deploys it to Cloud Run.
#
#   rp/deploy/gcp/deploy.sh <gcp-project> [region]
#
# The image is built by Cloud Build rather than on this machine: Cloud Run
# runs amd64, and a Mac would build arm64. Terraform describes what runs, not
# how it is built, so the build happens between two applies — the first makes
# the registry the image is pushed to, the second runs the image.
#
# Running this script is the approval: both applies go ahead without asking,
# since a non-interactive apply has no one to ask. To see what would change
# first, run `terraform plan` in this directory.
set -eu

project=${1:?usage: deploy.sh <gcp-project> [region]}
region=${2:-asia-northeast1}
here=$(cd "$(dirname "$0")" && pwd)
rp=$(cd "$here/../.." && pwd)

# Tag by commit, marked when what goes into the image has changes not yet
# committed, so what runs can always be traced to what was built. The time and
# a random suffix make the tag this build's alone: two builds of one commit —
# from two worktrees, say — never share it, so the digest looked up below is
# the one this build pushed.
tag=$(git -C "$rp" rev-parse --short HEAD)
[ -z "$(git -C "$rp" status --porcelain -- Dockerfile serve.py public)" ] || tag="$tag-dirty"
tag="$tag-$(date -u +%Y%m%dT%H%M%SZ)-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
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
terraform apply -input=false -auto-approve \
  -var "project=$project" -var "region=$region" -var "image=$repository:$tag" \
  -target=google_project_service.apis \
  -target=google_artifact_registry_repository.rp
gcloud builds submit "$rp" --project "$project" --tag "$repository:$tag"

# Run the build by digest, not by tag. A digest names the image itself, so
# what runs cannot change under the same name, and Terraform sees every build
# as a change to roll out.
digest=$(gcloud artifacts docker images describe "$repository:$tag" \
  --project "$project" --format='value(image_summary.digest)')
image="$repository@$digest"

# Recorded beside the state, in a file Terraform reads on its own, so a later
# plan or destroy in this directory needs no arguments. The file is the
# script's alone and is rewritten on every deploy; terraform.tfvars is left to
# whoever deploys, for settings such as the service name, and its values
# survive here. Terraform reads *.auto.tfvars after terraform.tfvars, so what
# this script was given wins. Like the state, both stay on this machine
# (.gitignore).
cat > "$here/deploy.auto.tfvars" <<VARS
project = "$project"
region  = "$region"
image   = "$image"
VARS
terraform apply -input=false -auto-approve
