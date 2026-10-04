# 永続リソース (クラスタを destroy しても残すもの)。ローカルから手動で1回 apply
# state 保管用バケット / CI 認証 (WIF) / サービスアカウント / Artifact Registry / 予算アラート

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 8.0" }
  }
  # 初回はローカル state。apply 後に下記を有効化し `terraform init -migrate-state` で GCS へ移行
  backend "gcs" { prefix = "bootstrap" } # bucket は -backend-config で指定
}

provider "google" {
  project = var.project_id
  region  = var.region
  # 予算 API はユーザー認証時に quota project の指定が必要
  billing_project       = var.project_id
  user_project_override = true
}

data "google_project" "this" {}

locals {
  services = [
    "artifactregistry", "billingbudgets", "cloudresourcemanager", "compute", "container",
    "iam", "iamcredentials", "serviceusage", "sts", "storage",
  ]
  # principal の URI 接頭辞
  pool = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}"
}

resource "google_project_service" "this" {
  for_each           = toset(local.services)
  service            = "${each.value}.googleapis.com"
  disable_on_destroy = false
}

# ---------- Terraform state ----------
resource "google_storage_bucket" "tfstate" {
  name                        = "${var.project_id}-tfstate"
  location                    = upper(var.region) # us-central1 なら 5GB まで無料枠
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  versioning { enabled = true } # state 破損時に過去版へ戻せる
  lifecycle_rule {
    condition { num_newer_versions = 5 }
    action { type = "Delete" }
  }
}

# ---------- Artifact Registry ----------
resource "google_artifact_registry_repository" "app" {
  repository_id = "app"
  location      = var.region
  format        = "DOCKER"
  # 無料枠 0.5GB に収めるため直近5件のみ保持
  cleanup_policy_dry_run = false
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions { keep_count = 5 }
  }
  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition { older_than = "86400s" }
  }
  depends_on = [google_project_service.this]
}

# ---------- GKE ノード用 SA (既定の Compute SA は権限過大のため専用 SA) ----------
resource "google_service_account" "node" {
  account_id = "gke-node"
}

resource "google_project_iam_member" "node" {
  for_each = toset([
    "roles/logging.logWriter", "roles/monitoring.metricWriter",
    "roles/monitoring.viewer", "roles/stackdriver.resourceMetadata.writer",
  ])
  project = var.project_id
  role    = each.value
  member  = google_service_account.node.member
}

resource "google_artifact_registry_repository_iam_member" "node_reader" {
  repository = google_artifact_registry_repository.app.name
  location   = var.region
  role       = "roles/artifactregistry.reader"
  member     = google_service_account.node.member
}

# ---------- GitHub Actions 用 Workload Identity Federation (鍵ファイル不要) ----------
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  depends_on                = [google_project_service.this]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  oidc { issuer_uri = "https://token.actions.githubusercontent.com" }
  attribute_mapping = {
    "google.subject"          = "assertion.sub"
    "attribute.repository_id" = "assertion.repository_id"
  }
  # このリポジトリの main ブランチ以外のトークンは拒否 (fork・他ブランチ・リポジトリ名乗っ取り対策に数値IDで判定)
  attribute_condition = "assertion.repository_id == '${var.github_repo_id}' && assertion.ref == 'refs/heads/main'"
}

# Terraform 実行用 SA: GitHub Environment "gcp" (承認必須) のジョブのみ使用可
resource "google_service_account" "terraform" {
  account_id = "gha-terraform"
}

resource "google_service_account_iam_member" "terraform_wif" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "${local.pool}/subject/repo:${var.github_repo}:environment:gcp"
}

# envs/dev (VPC + GKE) の作成に必要な最小限
resource "google_project_iam_member" "terraform" {
  for_each = toset(["roles/container.admin", "roles/compute.networkAdmin"])
  project  = var.project_id
  role     = each.value
  member   = google_service_account.terraform.member
}

resource "google_service_account_iam_member" "terraform_use_node_sa" {
  service_account_id = google_service_account.node.name
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.terraform.member
}

resource "google_storage_bucket_iam_member" "terraform_state" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.terraform.member
}

# イメージ push 用 SA: main ブランチのワークフローから使用
resource "google_service_account" "push" {
  account_id = "gha-push"
}

resource "google_service_account_iam_member" "push_wif" {
  service_account_id = google_service_account.push.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository_id/${var.github_repo_id}"
}

resource "google_artifact_registry_repository_iam_member" "push_writer" {
  repository = google_artifact_registry_repository.app.name
  location   = var.region
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.push.member
}

# ---------- 予算アラート (通知のみ。課金は止まらない) ----------
resource "google_billing_budget" "monthly" {
  billing_account = var.billing_account
  display_name    = "catchup-monthly"
  budget_filter { projects = ["projects/${data.google_project.this.number}"] }
  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = tostring(var.budget_amount)
    }
  }
  dynamic "threshold_rules" {
    for_each = [0.5, 0.9, 1.0]
    content { threshold_percent = threshold_rules.value }
  }
  depends_on = [google_project_service.this]
}
