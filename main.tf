#create a VPC for the project
resource "google_compute_network" "vpc_name" {
  for_each = {
    for index, name in var.vpc_name : name => index
  }
  name = each.key
  auto_create_subnetworks = false
  routing_mode = "REGIONAL"
  delete_default_routes_on_create = true
}

#create a "webapp" subnet for the VPC
resource "google_compute_subnetwork" "webapp" {
  for_each = google_compute_network.vpc_name
  name          = "${each.key}-webapp"
  ip_cidr_range = var.webapp_subnet_cidr
  region        = "us-east1"
  network       = each.value.self_link
}

#create a "db" subnet for the VPC
resource "google_compute_subnetwork" "db" {
  for_each = google_compute_network.vpc_name
  name          = "${each.key}-db"
  ip_cidr_range = var.db_subnet_cidr
  region        = "us-east1"
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
  for_each = google_compute_subnetwork.webapp
  name    = "${each.key}-allow-application-traffic"
  network = each.value.network

  allow {
    protocol = "tcp"
    ports    = ["8080"] # Replace with your application's port
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "deny_ssh" {
  for_each = google_compute_subnetwork.webapp
  name    = "${each.key}-deny-ssh"
  network = each.value.network

  deny {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

#Compute Engine instance with a custom boot disk
resource "google_compute_instance" "custom_instance" {
  for_each = google_compute_subnetwork.webapp
  name         = "${each.key}-instance"
  machine_type = "n1-standard-1" 
  zone         = "us-east1-b"    

  network_interface {
    subnetwork = each.value.self_link
  }

  boot_disk {
    initialize_params {
      image = var.custom_image  # dynamic variable for image url
      type  = "pd-balanced"
      size  = 100
    }
  }
  
}
