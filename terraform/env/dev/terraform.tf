terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 8.0" }
  }
  backend "gcs" {
    prefix = "dev" # 既存 state を継続利用。bucket は -backend-config で指定
  }
}
