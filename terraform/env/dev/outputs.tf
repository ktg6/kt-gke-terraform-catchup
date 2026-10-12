output "get_credentials" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.main.name} --zone ${var.zone} --project ${var.project_id}"
}

output "control_plane_version" {
  value = google_container_cluster.main.master_version
}

output "node_pool_version" {
  value = google_container_node_pool.spot.version
}
