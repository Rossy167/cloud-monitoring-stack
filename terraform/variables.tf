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
  description = "CIDR ranges allowed to SSH in. Defaults to open — override with your own IP/32 once you know it, e.g. [\"203.0.113.4/32\"]."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Set this in a terraform.tfvars file that you do NOT commit — see .gitignore."
  type        = string
  sensitive   = true
}
