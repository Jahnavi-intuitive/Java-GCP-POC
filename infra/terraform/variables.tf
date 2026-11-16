variable "project_id" {
  type        = string
  description = "GCP project that holds the POC"
}

variable "region" {
  type    = string
  default = "us-central1"
}