#create a VPC for the project
resource "google_compute_network" "vpc_name" {
  for_each = {
    for index, name in var.vpc_name : name => index
  }
  name = each.key
  auto_create_subnetworks = false
  routing_mode = var.routing_mode
  delete_default_routes_on_create = true
}

#create a "webapp" subnet for the VPC
resource "google_compute_subnetwork" "webapp" {
  for_each = google_compute_network.vpc_name
  name          = "${each.key}-webapp"
  ip_cidr_range = var.webapp_subnet_cidr
  region        = var.region
  network       = each.value.self_link
}

#create a "db" subnet for the VPC
resource "google_compute_subnetwork" "db" {
  for_each = google_compute_network.vpc_name
  name          = "${each.key}-db"
  ip_cidr_range = var.db_subnet_cidr
  region        = var.region
  network       = each.value.self_link
}

#defining routes
resource "google_compute_route" "webapp_route" {
    for_each = google_compute_network.vpc_name
    name                  = "${each.key}-webapp-route"
    network               = each.value.self_link
    dest_range            = "0.0.0.0/0"
    next_hop_gateway      = "default-internet-gateway"
}


# Firewall rule to allow traffic to the application port and deny SSH
resource "google_compute_firewall" "allow_application_traffic" {
  for_each = google_compute_network.vpc_name
  name    = "${each.key}-allow-application-traffic"
  network = each.value.self_link

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "deny_ssh" {
 for_each = google_compute_network.vpc_name
 name    = "${each.key}-deny-ssh"
 network = each.value.self_link

 deny {
   protocol = "tcp"
   ports    = ["22"]
 }

 source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_global_address" "private_ip_block" {
  for_each = toset(var.vpc_name)
  name         = "private-ip-block"
  purpose      = "VPC_PEERING"
  address_type = "INTERNAL"
  ip_version   = "IPV4"
  prefix_length = 16
  network       = google_compute_network.vpc_name[each.value].self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {
  for_each = toset(var.vpc_name)
  network       = google_compute_network.vpc_name[each.value].self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_block[each.value].name]
}

resource "google_sql_database_instance" "mysql_instance" {
  for_each      = google_compute_network.vpc_name
  name          = "mysql-instance-${each.key}"
  database_version = "MYSQL_8_0"
  region = var.region
  deletion_protection = false
  

  settings {
    tier = "db-f1-micro"
    availability_type = "REGIONAL"
    disk_type         = var.db_disk_type
    disk_size         = var.db_disk_size

    ip_configuration {
      ipv4_enabled  = false
      private_network = google_compute_network.vpc_name[each.key].self_link
    }

    backup_configuration{
      binary_log_enabled = true
      enabled = true
    }

}
  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "mysql_database" {
  for_each = google_compute_network.vpc_name
  name = var.sql_database_name
  instance = google_sql_database_instance.mysql_instance[each.key].name
}

resource "google_sql_user" "user" {
  for_each = google_compute_network.vpc_name
  name = "webapp-${each.key}"
  instance = google_sql_database_instance.mysql_instance[each.key].name
  password = random_password.password.result
}

resource "random_password" "password" {
  length           = 10
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

#Compute Engine instance with a custom boot disk
resource "google_compute_instance" "custom_instance" {
  for_each = google_compute_subnetwork.webapp
  name         = "${each.key}-instance"
  machine_type = var.machine_type
  zone         = var.zone  

  boot_disk {
    initialize_params {
      image = var.custom_image  # dynamic variable for image url
      type  = "pd-balanced"
      size  = 100
    }
  }

  network_interface {
    network    = google_compute_network.vpc_name[each.key].self_link
    subnetwork = each.value.self_link
    access_config {}
  }
  
  service_account {
    email  = google_service_account.webapp_service_acc.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
  
  metadata_startup_script = <<-EOF
    #!/bin/bash
    export DB_HOST="${google_sql_database_instance.mysql_instance[each.key].private_ip_address}"
    export DB_USER="${google_sql_user.user[each.key].name}"
    export DB_PASS="${random_password.password.result}"
    export DB_NAME="${google_sql_database.mysql_database[each.key].name}"
    
    echo "SQLALCHEMY_DATABASE_URI=mysql+pymysql://$DB_USER:$DB_PASS@$DB_HOST/$DB_NAME" > /opt/csye6225/db_properties.ini
    sudo chown csye6225:csye6225 /opt/csye6225/db_properties.ini
    sudo chmod 660 /opt/csye6225/db_properties.ini
    

  EOF

}

resource "google_dns_record_set" "a" {
  for_each = google_compute_instance.custom_instance
  managed_zone = var.dns_managed_zone
  name         = var.domain_name
  type         = "A"
  ttl          = 300
  rrdatas      = [each.value.network_interface[0].access_config[0].nat_ip]
}

#Service Account
resource "google_service_account" "webapp_service_acc" {
  account_id   = "webapp-service-acc"
  display_name = "VM Service Account"
}

#Bind IAM roles to the Service Account
resource "google_project_iam_binding" "logging_admin_binding" {
  project = var.project_id
  role    = "roles/logging.admin"
  
  members = [
    "serviceAccount:${google_service_account.webapp_service_acc.email}"
  ]
}

resource "google_project_iam_binding" "monitoring_metric_writer_binding" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  
  members = [
    "serviceAccount:${google_service_account.webapp_service_acc.email}"
  ]
}

resource "google_project_iam_binding" "pubsub_publisher_binding" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  
  members = [
    "serviceAccount:${google_service_account.webapp_service_acc.email}"
  ]
}

resource "google_storage_bucket" "cloud_functions_bucket" {
  name     = "dev-func-bucket"
  location = "US"
}

resource "google_cloudfunctions_function" "verify_email_function" {
  name        = "verify-email-id"
  description = "Sends verification emails to new users"
  runtime     = "python39"

  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.cloud_functions_bucket.name
  source_archive_object = google_storage_bucket_object.function_archive.name
  entry_point = "send_verification_email"

  environment_variables = {
    MAILGUN_DOMAIN = "bharathbhaskar.me"
    MAILGUN_API_KEY = "3aa5b7aec14341f5adb31b70619144ff-f68a26c9-44c6d1a4"
  }

  service_account_email = google_service_account.cloud_function_service_acc.email

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource = google_pubsub_topic.verify_email_topic.id
    failure_policy {
      retry = false
    }
  }
}


resource "google_storage_bucket_object" "function_archive" {
  name   = "verify-email-function.zip"
  bucket = google_storage_bucket.cloud_functions_bucket.name
  source = "./function.zip" 
}


resource "google_pubsub_topic" "verify_email_topic" {
  name = "verify_email_id"
}

resource "google_service_account" "cloud_function_service_acc" {
  account_id   = "cloud-function-service-acc"
  display_name = "Cloud Function Service Account"
}

resource "google_pubsub_subscription" "verify_email_subscription" {
  name  = "verify-email-subscription"
  topic = google_pubsub_topic.verify_email_topic.name
 
  ack_deadline_seconds = 20
}
