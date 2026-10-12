variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

# ---- アップグレード演習用 (任意)。未指定 ("") なら GKE の既定バージョン・自動更新のまま ----
variable "gke_version" {
  description = "初期コントロールプレーンの最小バージョン。指定版で作成される保証はないため実バージョンを確認する"
  type        = string
  default     = ""

  validation {
    condition     = var.gke_version == "" || can(regex("^1\\.[0-9]+\\.[0-9]+-gke\\.[0-9]+$", var.gke_version))
    error_message = "gke_version は 1.xx.y-gke.z 形式で指定する"
  }
}

variable "upgrade_exclusion_start" {
  description = "自動アップグレードを止める期間の開始日時 (UTC RFC3339)。演習直前の日時を指定する"
  type        = string
  default     = ""

  validation {
    condition     = var.upgrade_exclusion_start == "" || (can(formatdate("YYYY-MM-DD", var.upgrade_exclusion_start)) && endswith(var.upgrade_exclusion_start, "Z"))
    error_message = "upgrade_exclusion_start は UTC RFC3339 形式で指定する"
  }
}

variable "upgrade_exclusion_end" {
  description = "自動アップグレードを再開する日時 (UTC RFC3339)。開始から 90 日以内を指定する"
  type        = string
  default     = ""

  validation {
    condition     = var.upgrade_exclusion_end == "" || (can(formatdate("YYYY-MM-DD", var.upgrade_exclusion_end)) && endswith(var.upgrade_exclusion_end, "Z"))
    error_message = "upgrade_exclusion_end は UTC RFC3339 形式で指定する"
  }
}

variable "machine_type" {
  description = "8GB × 2台 = 計 16GB。4vCPU×1台とほぼ同額"
  type        = string
  default     = "e2-standard-2"
}

variable "node_count" {
  description = "DB の primary / replica を別ノードに置くため 2 台"
  type        = number
  default     = 2
}
