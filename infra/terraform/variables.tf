variable "project_id" {
  type        = string
  description = "GCP project that holds the POC"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "db_tier" {
  type    = string
  default = "db-f1-micro"
}