# 学習時に apply、終了時に destroy するリソース (VPC + GKE)

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 8.0" }
  }
  backend "gcs" {
    prefix = "dev" # bucket は -backend-config="bucket=..." で指定
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  # bootstrap で作成済みの SA
  node_sa = "gke-node@${var.project_id}.iam.gserviceaccount.com"
  # 開始・終了の両方が指定された時だけ自動アップグレードを止める
  upgrade_exclusion = var.upgrade_exclusion_start != "" && var.upgrade_exclusion_end != ""
}

resource "google_compute_network" "vpc" {
  name                    = "catchup"
  auto_create_subnetworks = false
}

# VPC ネイティブクラスタ用に Pod / Service のセカンダリ範囲を持つサブネット
resource "google_compute_subnetwork" "gke" {
  name                     = "gke"
  network                  = google_compute_network.vpc.id
  region                   = var.region
  ip_cidr_range            = "10.0.0.0/20"
  private_ip_google_access = true
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.16.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.32.0.0/20"
  }
}

resource "google_container_cluster" "main" {
  name     = "catchup"
  location = var.zone # ゾーンクラスタ: 管理手数料が GKE 無料枠で相殺される
  network  = google_compute_network.vpc.id

  subnetwork          = google_compute_subnetwork.gke.id
  deletion_protection = false # 学習用: destroy 可能に
  # 初期バージョンの下限 (GKE がより新しくする場合あり)。未指定なら既定バージョン
  min_master_version = var.gke_version != "" ? var.gke_version : null

  # 既定ノードプールは作成直後に削除し、下の node_pool で管理
  remove_default_node_pool = true
  initial_node_count       = 1
  node_config {
    service_account = local.node_sa
    disk_type       = "pd-standard"
    disk_size_gb    = 30
  }

  release_channel { channel = "REGULAR" }
  maintenance_policy {
    daily_maintenance_window { start_time = "03:00" }
    dynamic "maintenance_exclusion" {
      for_each = local.upgrade_exclusion ? [1] : []
      content {
        exclusion_name = "manual-upgrade-lab"
        start_time     = var.upgrade_exclusion_start
        end_time       = var.upgrade_exclusion_end
        exclusion_options { scope = "NO_UPGRADES" } # 最大 90 日
      }
    }
  }
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  workload_identity_config { workload_pool = "${var.project_id}.svc.id.goog" }
  gateway_api_config { channel = "CHANNEL_STANDARD" } # Gateway API CRD を GKE が管理

  # Cloud Logging / Monitoring はシステムのみ (監視は Datadog で学ぶ)
  logging_config { enable_components = ["SYSTEM_COMPONENTS"] }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus { enabled = false }
  }

  lifecycle {
    precondition {
      condition     = (var.upgrade_exclusion_start == "") == (var.upgrade_exclusion_end == "")
      error_message = "upgrade_exclusion_start / _end は両方空、または両方指定にする"
    }
    precondition {
      condition = !local.upgrade_exclusion || try(
        timecmp(var.upgrade_exclusion_start, var.upgrade_exclusion_end) < 0 &&
        timecmp(var.upgrade_exclusion_end, timeadd(var.upgrade_exclusion_start, "2160h")) <= 0,
        false
      )
      error_message = "upgrade_exclusion_end は開始より後、かつ開始から 90 日以内にする"
    }
  }
}

# min_master_version は下限指定のため、指定版で作成された保証はない → 実バージョンを確認 (不一致は警告のみ)
# 手動アップグレード後もこの警告が出る → gke_version を実バージョンに合わせる
check "gke_version" {
  assert {
    condition     = var.gke_version == "" || google_container_cluster.main.master_version == var.gke_version
    error_message = "コントロールプレーンの実バージョンが gke_version と異なる (terraform output control_plane_version で確認)"
  }
}

resource "google_container_node_pool" "spot" {
  name       = "spot"
  cluster    = google_container_cluster.main.id
  location   = var.zone
  node_count = var.node_count

  node_config {
    machine_type    = var.machine_type
    spot            = true # 通常の約 1/3 の料金。随時停止され得る
    disk_type       = "pd-standard"
    disk_size_gb    = 30
    service_account = local.node_sa
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    workload_metadata_config { mode = "GKE_METADATA" }
    shielded_instance_config { enable_secure_boot = true }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # 追加ノード (= 追加課金) を作らず 1 台ずつ更新。更新中は残り 1 台で稼働
  upgrade_settings {
    max_surge       = 0
    max_unavailable = 1
  }
}
