# VPC
resource "google_compute_network" "vpc" {
  name                    = "mtls-hack-vpc"
  auto_create_subnetworks = "false"
  project                 = var.project_id
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  count = var.num_clusters

  name          = "${var.base_name}-${count.index}"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.self_link

  private_ip_google_access = true

  ip_cidr_range = "10.0.${count.index * 2}.0/24"

  secondary_ip_range {
    range_name    = "k8s-service-range"
    ip_cidr_range = "10.0.${count.index * 2 + 1}.0/24"
  }
  secondary_ip_range {
    range_name    = "k8s-pod-range"
    ip_cidr_range = "10.${count.index + 10}.0.0/16"
  }
}

# support `gcloud beta compute ssh --tunnel-through-iap`
resource "google_compute_firewall" "firewall" {
  name    = "mtls-hack-fw-rule"
  project = var.project_id
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = [
    "10.0.0.0/8",      # Allow internal traffic
    "35.235.240.0/20", # Allow Google's jump-hosts
  ]
}
