variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "billing_account" {
  description = "gcloud billing accounts list で確認 (XXXXXX-XXXXXX-XXXXXX)"
  type        = string
}

variable "budget_amount" {
  description = "月額予算。請求先アカウントの通貨単位"
  type        = number
  default     = 1500
}

variable "budget_currency" {
  description = "請求先アカウントの通貨と一致させる"
  type        = string
  default     = "JPY"
}

variable "github_repo" {
  description = "owner/name"
  type        = string
  default     = "ktg6/kt-gke-terraform-catchup"
}

variable "github_repo_id" {
  description = "gh api repos/OWNER/NAME --jq .id"
  type        = string
  default     = "1388421027"
}

variable "github_owner_id" {
  description = "gh api users/OWNER --jq .id (immutable subject の sub に含まれる)"
  type        = string
  default     = "16849557"
}
