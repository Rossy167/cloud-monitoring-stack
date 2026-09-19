variable "project_id" {
  description = "GCP project ID to deploy into."
  type        = string
}

variable "region" {
  description = "GCP region. Must be one of the Always Free e2-micro regions: us-west1, us-central1, us-east1."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone within the chosen region."
  type        = string
  default     = "us-central1-a"
}

variable "instance_name" {
  description = "Name of the compute instance."
  type        = string
  default     = "monitoring-vm"
}

variable "machine_type" {
  description = "e2-micro is the Always Free tier machine type — do not change unless you're OK being billed."
  type        = string
  default     = "e2-micro"
}

variable "ssh_user" {
  description = "Username to create on the VM and use for SSH."
  type        = string
}

variable "ssh_pub_key_path" {
  description = "Path to your SSH public key, e.g. ~/.ssh/id_ed25519.pub"
  type        = string
}

variable "ssh_source_ranges" {
  description = "CIDR ranges allowed to SSH in. Required — no default, to force a conscious choice instead of silently allowing the world. Set to your own IP/32, e.g. [\"203.0.113.4/32\"]."
  type        = list(string)
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Set this in a terraform.tfvars file that you do NOT commit — see .gitignore."
  type        = string
  sensitive   = true
}

variable "alertmanager_webhook_url" {
  description = "Webhook URL Alertmanager sends notifications to (e.g. a Slack incoming webhook, PagerDuty, or a custom endpoint). Optional — leave as the default empty string to disable notifications; Alertmanager runs with a no-op receiver and simply swallows alerts instead of failing to start. Set this in a terraform.tfvars file that you do NOT commit — see .gitignore."
  type        = string
  sensitive   = true
  default     = ""
}

variable "iap_ssh_accessor_email" {
  description = "Google account email (e.g. \"you@gmail.com\") to grant roles/iap.tunnelResourceAccessor on the monitoring VM, so that identity can open an IAP SSH tunnel (`gcloud compute ssh --tunnel-through-iap`). Required — no default, since this is personal to whoever runs apply and must not be guessed/hardcoded. Set this in a terraform.tfvars file that you do NOT commit — see .gitignore."
  type        = string
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key, used by the VM to join your tailnet non-interactively on first boot (generate one at https://login.tailscale.com/admin/settings/keys). Optional — leave as the default empty string to skip installing/joining Tailscale entirely; this is a second, independent SSH path alongside ssh_source_ranges/IAP, not a requirement. This is a real secret: set it in a terraform.tfvars file that you do NOT commit — see .gitignore."
  type        = string
  sensitive   = true
  default     = ""
}
