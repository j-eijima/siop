# The test RP on Cloud Run. Cloud Run's own https URL is what makes the RP
# usable from a phone: WebCrypto needs a secure context, and Section 3.2.2.1
# wants an https redirect_uri (docs/decisions/0006, 0013, 0014).

locals {
  apis = [
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.apis)
  service  = each.value

  # Turning an API off on destroy would break anything else in the project
  # that uses it.
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "rp" {
  location      = var.region
  repository_id = "siop"
  format        = "DOCKER"
  description   = "Images of the SIOP test RP"

  # Every deploy pushes an image of its own. Keep the last few, so
  # a bad deploy can be rolled back, and let the rest go.
  cleanup_policy_dry_run = false
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }
  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      older_than = "2592000s" # 30 days
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_service" "rp" {
  name     = var.service
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  # A test RP holds nothing worth protecting from `terraform destroy`.
  deletion_protection = false

  # Scaling is set per revision, in the template below. Cloud Run fills in the
  # service-wide block with zeros of its own, which Terraform would otherwise
  # offer to clear on every plan without changing anything.
  lifecycle {
    ignore_changes = [scaling]
  }

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = var.image

      # serve.py listens on $PORT, which Cloud Run sets to this.
      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
        cpu_idle = true
      }
    }
  }

  depends_on = [google_project_service.apis]
}

# Anyone may open it: a phone reaching the RP carries no Google credentials,
# and the RP serves static files that verify in the browser.
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.rp.name
  location = google_cloud_run_v2_service.rp.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
