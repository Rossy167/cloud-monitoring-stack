terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Partial backend configuration on purpose: the bucket name/prefix are
  # account-specific and must not be hardcoded/committed here. Supply them
  # at `terraform init` time with -backend-config flags. See README.md for
  # the one-time setup steps.
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
