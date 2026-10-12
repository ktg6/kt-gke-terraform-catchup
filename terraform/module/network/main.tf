resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

# VPC ネイティブクラスタ用に Pod / Service のセカンダリ範囲を持つサブネット
resource "google_compute_subnetwork" "gke" {
  name                     = var.subnetwork_name
  network                  = google_compute_network.vpc.id
  region                   = var.region
  ip_cidr_range            = var.subnetwork_cidr
  private_ip_google_access = true
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}
