output "registry_url" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}"
  description = "Docker image path prefix"
}

output "vpc_name" {
  value = google_compute_network.vpc.name
}