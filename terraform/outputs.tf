output "instance_ip" {
  description = "The VM's static public IP."
  value       = google_compute_address.monitoring_ip.address
}

output "grafana_url" {
  description = "Public HTTPS URL for the Grafana dashboard, once the VM has finished booting (give it 2-3 minutes)."
  value       = "https://${google_compute_address.monitoring_ip.address}.sslip.io"
}

output "ssh_command" {
  description = "Command to SSH into the VM."
  value       = "ssh ${var.ssh_user}@${google_compute_address.monitoring_ip.address}"
}
