resource "random_id" "db_suffix" {
  byte_length = 2
}

resource "google_sql_database_instance" "main" {
  name                = "trebol-poc-db-${random_id.db_suffix.hex}"
  region              = var.region
  database_version    = "MYSQL_8_0"
  deletion_protection = true

  settings {
    tier                        = var.db_tier
    edition                     = "ENTERPRISE"
    availability_type           = "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = 10
    disk_autoresize             = true
    disk_autoresize_limit       = 20
    deletion_protection_enabled = true
    activation_policy           = "ALWAYS"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled    = true
      start_time = "03:00"

      backup_retention_settings {
        retained_backups = 3
      }
    }
  }

  depends_on = [google_service_networking_connection.psa]

  lifecycle {
    ignore_changes = [settings[0].activation_policy]
  }
}

resource "google_sql_database" "app" {
  name     = "trebol"
  instance = google_sql_database_instance.main.name
  charset  = "utf8mb4"
}

resource "google_sql_user" "app" {
  name     = "trebol_app"
  instance = google_sql_database_instance.main.name
  host     = "%"
  password = random_password.db_password.result
}