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

# Needed for Identity-Aware Proxy TCP forwarding (`gcloud compute ssh
# --tunnel-through-iap`) to work at all — same rationale as compute.googleapis.com
# above: enable it here so a fresh project doesn't need a manual
# `gcloud services enable iap.googleapis.com` step first.
resource "google_project_service" "iap" {
  project            = var.project_id
  service            = "iap.googleapis.com"
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

# Second, independent SSH path alongside allow_ssh above — additive, not a
# replacement. allow_ssh (IP-allowlisted via ssh_source_ranges) is untouched
# and still required for direct SSH; this rule only opens 22 to Google's
# fixed, published Identity-Aware Proxy source range. That range is
# controlled by Google and does not change, so — unlike ssh_source_ranges —
# it never needs updating when the human's home IP changes. Traffic still
# has to pass through IAP's own auth (see the IAM binding below) before it
# ever reaches this rule; this alone does not open SSH to the internet.
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  network = google_compute_network.monitoring_vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
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
      ssh_user           = var.ssh_user
      tailscale_auth_key = var.tailscale_auth_key

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

      reboot_required_script_b64     = base64encode(file("${path.module}/../monitoring/scripts/reboot-required-metric.sh"))
      unattended_upgrades_auto_b64   = base64encode(file("${path.module}/../monitoring/unattended-upgrades/20auto-upgrades"))
      unattended_upgrades_config_b64 = base64encode(file("${path.module}/../monitoring/unattended-upgrades/50unattended-upgrades"))
    })
  }
}

# Grants the human's own Google identity permission to open an IAP tunnel to
# this specific instance (gcloud compute ssh --tunnel-through-iap). Scoped to
# just this instance, not the whole project — roles/iap.tunnelResourceAccessor
# at instance level is the minimal grant that makes the tunnel work, rather
# than a project-wide binding that would also cover any future instances.
#
# NOTE: this must be google_iap_tunnel_instance_iam_member, not
# google_compute_instance_iam_member. The latter is for general compute
# instance IAM roles (instance admin, OS Login, etc.) and rejects
# roles/iap.tunnelResourceAccessor at apply time with a 400
# "Role ... is not supported for this resource" / invalidIamPolicy error —
# the API's IAM policy container for IAP TCP-tunnel access on an instance is
# a distinct resource from the compute instance's own IAM policy, and the
# provider models that as this separate resource type. Also note the field
# is `instance`, not `instance_name` (which is what google_compute_instance_iam_member
# uses).
resource "google_iap_tunnel_instance_iam_member" "iap_tunnel_accessor" {
  project  = var.project_id
  zone     = var.zone
  instance = google_compute_instance.monitoring_vm.name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = "user:${var.iap_ssh_accessor_email}"

  depends_on = [google_project_service.iap]
}
