terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 8.0" }
  }
  # 初回はローカル state。apply 後に下記を有効化し `terraform init -migrate-state` で GCS へ移行
  backend "gcs" { prefix = "bootstrap" } # bucket は -backend-config で指定
}
