locals {
  timeout = "30m"
}

resource "google_container_cluster" "cluster" {
  count = var.num_clusters

  name     = "${var.base_name}-${count.index}"
  location = var.zone
  project  = var.project_id

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = false

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet[count.index].name

  ip_allocation_policy {
    cluster_secondary_range_name  = "k8s-pod-range"
    services_secondary_range_name = "k8s-service-range"
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Set to empty block, to block the public endpoint
  master_authorized_networks_config { }

  control_plane_endpoints_config {
    dns_endpoint_config {
        allow_external_traffic = true
    }
  }

  workload_identity_config {
   workload_pool = "${var.project_id}.svc.id.goog"
  }
}

# Separately Managed Node Pool
resource "google_container_node_pool" "nodepool" {
  count = var.num_clusters

  name       = "${google_container_cluster.cluster[count.index].name}-node-pool"
  location   = var.zone
  project    = var.project_id
  cluster    = google_container_cluster.cluster[count.index].name

  initial_node_count = 1

  node_config {
    // These scopes are needed for the GKE nodes' service account to have pull rights to GCR.
    // Default is "https://www.googleapis.com/auth/logging.write" and "https://www.googleapis.com/auth/monitoring".
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/userinfo.email",
    ]

    labels = {
      env = var.project_id
    }

    machine_type = "e2-standard-4"
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  timeouts {
    create = local.timeout
    update = local.timeout
    delete = local.timeout
  }
}
