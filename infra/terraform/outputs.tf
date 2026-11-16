output "registry_url" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}"
  description = "Docker image path prefix"
}

output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "db_instance_name" {
  value = google_sql_database_instance.main.name
}

output "db_private_ip" {
  value = google_sql_database_instance.main.private_ip_address
}

output "runtime_sa_email" {
  value = google_service_account.runtime.email
}