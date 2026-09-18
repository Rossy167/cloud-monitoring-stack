# --- APIs ---
# On a fresh GCP project, compute.googleapis.com isn't enabled yet, and the
# very first google_compute_* resource Terraform tries to create will fail
# with a 403. Enabling it here (instead of requiring a manual
# `gcloud services enable` step first) means `terraform apply` works
# unattended on a brand-new project, as long as the identity running apply
# has serviceusage.services.enable (Owner/Editor roles include it).
#
# disable_on_destroy = false: this is a project-level, potentially shared
# API — `terraform destroy` on this stack should not disable it for the
# whole project.

resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# --- Networking ---
# A dedicated VPC + subnet rather than the GCP default network, so the
# network topology here is explicit and intentional rather than implicit.

resource "google_compute_network" "monitoring_vpc" {
  name                    = "monitoring-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "monitoring_subnet" {
  name          = "monitoring-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.monitoring_vpc.id

  depends_on = [google_project_service.compute]
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

  depends_on = [google_project_service.compute]
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

  depends_on = [google_project_service.compute]
}

# --- Static IP ---
# Reserved so the address survives VM restarts — needed since the sslip.io
# hostname and TLS cert are both tied to this specific IP.

resource "google_compute_address" "monitoring_ip" {
  name   = "monitoring-static-ip"
  region = var.region

  depends_on = [google_project_service.compute]
}

# --- Compute instance ---

resource "google_compute_instance" "monitoring_vm" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["monitoring-vm"]

  depends_on = [google_project_service.compute]

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

  # NOTE: this must be metadata["user-data"], not metadata_startup_script.
  # metadata_startup_script sets GCP's "startup-script" key, which is run
  # verbatim as a bash script by google-startup-scripts.service — it is NOT
  # parsed by cloud-init. Our cloud-init.yaml.tftpl is a #cloud-config YAML
  # document (packages/write_files/runcmd), which only cloud-init's own
  # datasource understands, and it only reads that from the "user-data"
  # metadata key. Putting cloud-config content in metadata_startup_script
  # silently fails: bash chokes on nearly every YAML line as "command not
  # found" and the script dies partway through with a syntax error, so
  # nothing in write_files/runcmd (docker install, the whole stack) ever
  # runs, even though `cloud-init status` still reports "done" (it ran its
  # own default modules fine — it just never saw our user-data at all).
  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_pub_key_path)}"

    user-data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      ssh_user = var.ssh_user

      docker_compose_b64 = base64encode(templatefile("${path.module}/../monitoring/docker-compose.yml.tftpl", {
        grafana_admin_password = var.grafana_admin_password
      }))

      prometheus_b64 = base64encode(templatefile("${path.module}/../monitoring/prometheus/prometheus.yml.tftpl", {
        static_ip = google_compute_address.monitoring_ip.address
      }))
      prometheus_rules_b64 = base64encode(file("${path.module}/../monitoring/prometheus/rules/alerts.yml"))
      blackbox_b64         = base64encode(file("${path.module}/../monitoring/blackbox/blackbox.yml"))

      alertmanager_b64 = base64encode(templatefile("${path.module}/../monitoring/alertmanager/alertmanager.yml.tftpl", {
        alertmanager_webhook_url = var.alertmanager_webhook_url
      }))

      caddyfile_b64 = base64encode(templatefile("${path.module}/../monitoring/caddy/Caddyfile.tftpl", {
        static_ip = google_compute_address.monitoring_ip.address
      }))

      grafana_datasource_b64             = base64encode(file("${path.module}/../monitoring/grafana/provisioning/datasources/datasource.yml"))
      grafana_dashboard_provisioning_b64 = base64encode(file("${path.module}/../monitoring/grafana/provisioning/dashboards/dashboard.yml"))
      grafana_dashboard_json_b64         = base64encode(file("${path.module}/../monitoring/grafana/dashboards/infra-overview.json"))
      fail2ban_script_b64                = base64encode(file("${path.module}/../monitoring/scripts/fail2ban-metrics.sh"))
      fail2ban_jail_local_b64            = base64encode(file("${path.module}/../monitoring/fail2ban/jail.local"))
    })
  }
}
