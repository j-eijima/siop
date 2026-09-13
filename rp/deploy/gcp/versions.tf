terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region

  # Charge API calls to the RP's project, whatever project the credentials
  # were set up with — otherwise enabling an API here can be refused for want
  # of it in some unrelated project.
  billing_project       = var.project
  user_project_override = true
}
