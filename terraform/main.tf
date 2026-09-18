# --- Networking ---
# A dedicated VPC + subnet rather than the GCP default network, so the
# network topology here is explicit and intentional rather than implicit.

resource "google_compute_network" "monitoring_vpc" {
  name                    = "monitoring-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "monitoring_subnet" {
  name          = "monitoring-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.monitoring_vpc.id
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.monitoring_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["monitoring-vm"]
}

resource "google_compute_firewall" "allow_http_https" {
  name    = "allow-http-https"
  network = google_compute_network.monitoring_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  # Needs to be open to the world: Grafana is meant to be publicly viewable,
  # and Let's Encrypt's HTTP-01 challenge for the sslip.io cert needs port 80
  # reachable from the internet to validate domain ownership.
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["monitoring-vm"]
}

# --- Static IP ---
# Reserved so the address survives VM restarts — needed since the sslip.io
# hostname and TLS cert are both tied to this specific IP.

resource "google_compute_address" "monitoring_ip" {
  name   = "monitoring-static-ip"
  region = var.region
}

# --- Compute instance ---

resource "google_compute_instance" "monitoring_vm" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["monitoring-vm"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 30 # GB — stays within the Always Free 30GB standard persistent disk allowance
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.monitoring_vpc.id
    subnetwork = google_compute_subnetwork.monitoring_subnet.id

    access_config {
      nat_ip = google_compute_address.monitoring_ip.address
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_pub_key_path)}"
  }

  metadata_startup_script = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    ssh_user = var.ssh_user

    docker_compose_b64 = base64encode(templatefile("${path.module}/../monitoring/docker-compose.yml.tftpl", {
      grafana_admin_password = var.grafana_admin_password
    }))

    prometheus_b64 = base64encode(templatefile("${path.module}/../monitoring/prometheus/prometheus.yml.tftpl", {
      static_ip = google_compute_address.monitoring_ip.address
    }))
    blackbox_b64   = base64encode(file("${path.module}/../monitoring/blackbox/blackbox.yml"))

    caddyfile_b64 = base64encode(templatefile("${path.module}/../monitoring/caddy/Caddyfile.tftpl", {
      static_ip = google_compute_address.monitoring_ip.address
    }))

    grafana_datasource_b64             = base64encode(file("${path.module}/../monitoring/grafana/provisioning/datasources/datasource.yml"))
    grafana_dashboard_provisioning_b64 = base64encode(file("${path.module}/../monitoring/grafana/provisioning/dashboards/dashboard.yml"))
    grafana_dashboard_json_b64         = base64encode(file("${path.module}/../monitoring/grafana/dashboards/infra-overview.json"))
    fail2ban_script_b64                = base64encode(file("${path.module}/../monitoring/scripts/fail2ban-metrics.sh"))
  })
}
