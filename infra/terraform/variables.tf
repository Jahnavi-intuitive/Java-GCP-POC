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
  default = "db-custom-2-7680"
}

variable "image" {
  type        = string
  description = "Full image path for the first deploy"
}

variable "max_instances" {
  type    = number
  default = 30
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

variable "swagger_enabled" {
  description = "Enable Swagger UI and /v3/api-docs in prod (the service stays IAM-protected)"
  type        = bool
  default     = true
}
