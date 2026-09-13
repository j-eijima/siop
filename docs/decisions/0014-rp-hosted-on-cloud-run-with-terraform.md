# 0014 — The hosted RP is Cloud Run, described in Terraform, with the image built apart

## Context

The RP has to be reachable over https before a phone can verify anything with it
([0006](0006-rp-verifies-in-the-browser.md)), and before its redirect_uri is within Section 3.2.2.1
([0013](0013-rp-reports-its-own-http-redirect.md)). Cloud Run gives a service an https URL with a
certificate every device already trusts, and `serve.py` takes its port from `$PORT`, so the
existing Dockerfile runs there unchanged.

A one-off `gcloud run deploy --source` works, but leaves nothing that says what was created: the
image registry, the APIs, who may invoke the service.

## Decision

The deployment is described in Terraform under `rp/deploy/gcp/`: the APIs, an Artifact Registry
repository that keeps the recent images and lets the rest expire, the Cloud Run service scaled to
zero, and invocation open to everyone — a phone opening the RP carries no Google credentials, and
there is nothing behind the page to protect.

Terraform does not build the image. Cloud Build does, tagged with the commit and a suffix unique to
the build: Cloud Run runs amd64, which a Mac does not build by default, and Terraform describes what
runs rather than how it is made. The service runs the image by digest, looked up by that tag, so
what runs is the image this build pushed and no other.
`deploy.sh` applies once to create the registry, builds, then applies again. It applies without
asking: running the script is the approval, and `terraform plan` shows beforehand what it would
change.

Each cloud gets a directory of its own under `rp/deploy/`. Terraform reads every `.tf` file in a
directory as one configuration, so a second cloud beside the first would collide with it — the same
variable and output names — and share its state.

The state stays on the machine that deploys, and is not committed. So do the variables of the last
deploy, which `deploy.sh` writes beside it so that later commands there need no arguments — to a
file of its own, `deploy.auto.tfvars`, never to `terraform.tfvars`, which holds the deployer's own
settings such as the service name and so survives every deploy.

## Consequences

Anyone with the URL can use the RP. It serves static files and verifies in the browser, so that
exposes nothing but the page.

The state on one machine is the only record of what Terraform made, and of which project it made it
in; losing it means importing the resources or recreating them. A remote backend is the step to take once more than one person
deploys.

On Cloud Run the RP's default redirect_uri is https, so the warning 0013 describes does not appear
there.
