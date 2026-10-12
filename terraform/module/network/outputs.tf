output "network_id" {
  value = google_compute_network.vpc.id
}

output "subnetwork_id" {
  value = google_compute_subnetwork.gke.id
}

output "pods_range_name" {
  value = google_compute_subnetwork.gke.secondary_ip_range[0].range_name
}

output "services_range_name" {
  value = google_compute_subnetwork.gke.secondary_ip_range[1].range_name
}
