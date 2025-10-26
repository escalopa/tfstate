terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }

  backend "s3" {
    endpoints = {
      s3 = "https://storage.yandexcloud.net"
    }
    region = "ru-central1"
    
    bucket = "escalopa-tfstate"
    key    = "terraform.tfstate"
  
    workspace_key_prefix = ""

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }

  required_version = ">= 0.13"
}

variable "token" {
  type        = string
  sensitive   = true
  description = "OAuth token for Yandex Cloud"
}

variable "cloud_id" {
  type        = string
  description = "Yandex Cloud ID"
}

variable "folder_id" {
  type        = string
  description = "Folder ID for terraform management infrastructure"
}

variable "managed_folders" {
  type        = map(string)
  description = "Map of folder names to folder IDs that this service account will manage"
  # Example:
  # {
  #   "env"  = "b1gxxxxxxxxxxxxxxxxxx"
  #   "prod" = "b1gxxxxxxxxxxxxxxxxxx"
  # }
}

provider "yandex" {
  token     = var.token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
}

###########################
### Service Account
###########################

resource "yandex_iam_service_account" "terraform_sa" {
  name        = "terraform-sa"
  description = "Service account for Terraform to manage all environments"
  folder_id   = var.folder_id
}

###########################
### Grant Permissions to All Managed Folders
###########################

# Grant admin role to each managed folder
resource "yandex_resourcemanager_folder_iam_member" "terraform_sa_admin" {
  for_each = var.managed_folders
  
  folder_id = each.value
  role      = "admin"
  member    = "serviceAccount:${yandex_iam_service_account.terraform_sa.id}"
}

# Gradn ydb.editor to create and manage ydb instances
resource "yandex_resourcemanager_folder_iam_member" "terraform_sa_ydb" {
  folder_id = var.folder_id
  role      = "ydb.editor"
  member    = "serviceAccount:${yandex_iam_service_account.terraform_sa.id}"
}

###########################
### Service Account Keys
###########################

# Key file for Terraform provider authentication
resource "yandex_iam_service_account_key" "terraform_sa_key" {
  service_account_id = yandex_iam_service_account.terraform_sa.id
  description        = "Key for Terraform provider authentication"
  key_algorithm      = "RSA_2048"
}

# Static access keys for S3 backend
resource "yandex_iam_service_account_static_access_key" "terraform_sa_s3_keys" {
  service_account_id = yandex_iam_service_account.terraform_sa.id
  description        = "Static keys for S3 backend access"
}

resource "local_file" "iam_json" {
  content = jsonencode({
    id                  = yandex_iam_service_account_key.terraform_sa_key.id
    service_account_id  = yandex_iam_service_account_key.terraform_sa_key.service_account_id
    created_at          = yandex_iam_service_account_key.terraform_sa_key.created_at
    key_algorithm       = yandex_iam_service_account_key.terraform_sa_key.key_algorithm
    public_key          = yandex_iam_service_account_key.terraform_sa_key.public_key
    private_key         = yandex_iam_service_account_key.terraform_sa_key.private_key
  })
  filename = "${path.module}/iam.json"
}


resource "local_file" "key_json" {
  content = jsonencode({
    access_key = yandex_iam_service_account_static_access_key.terraform_sa_s3_keys.access_key
    secret_key = yandex_iam_service_account_static_access_key.terraform_sa_s3_keys.secret_key
  })
  filename = "${path.module}/key.json"
}

###########################
### S3 Bucket for Terraform State
###########################

resource "yandex_storage_bucket" "terraform_state" {
  bucket    = "escalopa-tfstate"
  folder_id = var.folder_id
  
  # No size limit for state files
  max_size = 5368709120 # 5 GB (more than enough)

  # Enable versioning for state file history
  versioning {
    enabled = true
  }

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
}

###########################
### Outputs
###########################

output "s3_access_key" {
  value       = yandex_iam_service_account_static_access_key.terraform_sa_s3_keys.access_key
  description = "S3 access key for Terraform backend"
}

output "s3_secret_key" {
  value       = yandex_iam_service_account_static_access_key.terraform_sa_s3_keys.secret_key
  sensitive   = true
  description = "S3 secret key for Terraform backend"
}

output "terraform_state_bucket" {
  value       = yandex_storage_bucket.terraform_state.bucket
  description = "Bucket name for Terraform state files"
}
