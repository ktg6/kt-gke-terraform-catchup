# GitHub の Actions Variables に登録する値
output "github_variables" {
  value = {
    GCP_PROJECT_ID  = var.project_id
    GCP_REGION      = var.region
    WIF_PROVIDER    = google_iam_workload_identity_pool_provider.github.name
    TF_SA           = google_service_account.terraform.email
    PUSH_SA         = google_service_account.push.email
    TF_STATE_BUCKET = google_storage_bucket.tfstate.name
  }
}
