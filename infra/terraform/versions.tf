terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  backend "gcs" {
    bucket = "trebol-poc-tfstate-itp-agentspace"
    prefix = "trebol/prod"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    owner = "jahnavi"
    poc   = "trebol"
  }
}