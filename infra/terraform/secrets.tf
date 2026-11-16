resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

locals {
  secret_names = toset(["db-password", "jwt-secret", "admin-password-hash"])
}

resource "google_secret_manager_secret" "s" {
  for_each  = local.secret_names
  secret_id = "trebol-poc-${each.key}"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.s["db-password"].id
  secret_data = random_password.db_password.result
}

resource "google_secret_manager_secret_version" "jwt_secret" {
  secret      = google_secret_manager_secret.s["jwt-secret"].id
  secret_data = random_password.jwt_secret.result
}