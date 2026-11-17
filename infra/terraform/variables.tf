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

variable "image" {
  type        = string
  description = "Full image path for the first deploy"
}

variable "max_instances" {
  type    = number
  default = 10
}

variable "cors_allowed_origins" {
  type    = string
  default = "http://localhost:3000"
}

variable "allow_public_access" {
  type    = bool
  default = false
}

variable "github_repository" {
  type    = string
  default = "Jahnavi-intuitive/Java-GCP-POC"
}

variable "alert_email" {
  description = "Where alert emails are sent"
  type        = string
  default     = "jahnavi.patel@intuitive.ai"
}