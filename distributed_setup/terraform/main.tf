terraform {
  required_version = "~> 1.4.6"

  backend "local" {
    path = ".data/terraform.tfstate"
  }

  required_providers {
      google = {
        source  = "google"
        version = "~> 6.27.0"
      }

      google-beta = {
        source  = "google-beta"
        version = "~> 6.27.0"
      }
  }
}

variable "project_id" {
  description = "project id"
  type        = string
}

variable "region" {
  description = "region"
}

variable "zone" {
  type = string
}

data "google_client_config" "default" {
  provider = google
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

variable "num_clusters" {
  type = number
}

variable "base_name" {
  type = string
}