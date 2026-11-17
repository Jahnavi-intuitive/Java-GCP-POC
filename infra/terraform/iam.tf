resource "google_service_account" "runtime" {
  account_id   = "trebol-poc-run"
  display_name = "trebol POC Cloud Run runtime"
}

resource "google_service_account" "ci_push" {
  account_id   = "trebol-poc-ci-push"
  display_name = "trebol POC CI image push"
}

resource "google_service_account" "ci_deploy" {
  account_id   = "trebol-poc-ci-deploy"
  display_name = "trebol POC CI deploy"
}

resource "google_secret_manager_secret_iam_member" "runtime_access" {
  for_each  = google_secret_manager_secret.s
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_artifact_registry_repository_iam_member" "ci_push_writer" {
  repository = google_artifact_registry_repository.app.name
  location   = google_artifact_registry_repository.app.location
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.ci_push.email}"
}