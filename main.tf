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
  ip_cidr_range = "10.1.0.0/24"
  region        = "us-east1"
  network       = each.value.self_link
}

#create a "db" subnet for the VPC
resource "google_compute_subnetwork" "db" {
  for_each = google_compute_network.vpc_name
  name          = "${each.key}-db"
  ip_cidr_range = "10.2.0.0/24"
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