provider "google" {
  project = var.project_id
  region  = var.region
  # 予算 API はユーザー認証時に quota project の指定が必要
  billing_project       = var.project_id
  user_project_override = true
}
