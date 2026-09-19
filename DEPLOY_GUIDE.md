# Deploy Guide

Everything in this repo has been reviewed and merged to `main`. Nothing has been applied to a real GCP project yet — that part is yours, deliberately: no agent in this workflow is permitted to run `terraform apply`, `terraform plan`, or any `gcloud` command. This is the exact sequence to run it yourself.

## 0. Prerequisites

- A GCP project with billing enabled.
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5 — `brew install terraform` on macOS.
- `gcloud` CLI authenticated: `gcloud auth application-default login`.
- An SSH key pair — `ssh-keygen -t ed25519` if you don't have one.
- Your own public IP, for locking down SSH: `curl -s ifconfig.me`.

You do **not** need to manually run `gcloud services enable compute.googleapis.com` — Terraform does this itself on first `apply` (see `terraform/main.tf`'s `google_project_service.compute` resource). The identity running `apply` just needs `serviceusage.services.enable`, which Owner/Editor roles already include.

## 1. One-time remote state bucket

Terraform state is stored in GCS, not locally — this is deliberately **not** Terraform code (a resource can't create the bucket that stores the state describing that resource):

```bash
gsutil mb -l us-central1 gs://YOUR_UNIQUE_BUCKET_NAME
gsutil versioning set on gs://YOUR_UNIQUE_BUCKET_NAME
```

Pick a globally-unique bucket name. This bucket is the one thing in this project that falls outside the GCP Always Free tier — typically a few cents/month.

## 2. Configure variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and fill in:

| Variable | Notes |
|---|---|
| `project_id` | Your GCP project ID |
| `ssh_user` | Username to create on the VM |
| `ssh_pub_key_path` | e.g. `~/.ssh/id_ed25519.pub` |
| `ssh_source_ranges` | Your IP as `["YOUR_IP/32"]` — **no default on purpose**, `apply` will refuse to run without it |
| `grafana_admin_password` | Pick something new, not reused elsewhere |
| `alertmanager_webhook_url` | Optional — leave commented out to run Alertmanager as a safe no-op |
| `iap_ssh_accessor_email` | Your Google account email — **no default on purpose**, `apply` will refuse to run without it. Grants that identity an IP-independent SSH path via IAP; see step 6 below |
| `tailscale_auth_key` | Optional — generate at https://login.tailscale.com/admin/settings/keys for a third, IP-independent SSH path. Leave commented out to skip Tailscale entirely |

`terraform.tfvars` is gitignored. Never commit it — it holds your Grafana password.

## 3. Init and apply

```bash
terraform init \
  -backend-config="bucket=YOUR_UNIQUE_BUCKET_NAME" \
  -backend-config="prefix=terraform/state"

terraform apply
```

Review the plan. It should create: two project services (Compute API, IAP API), a VPC + subnet, three firewall rules (22 from your IP only, 22 from Google's fixed IAP range, 80/443 from anywhere), a static IP, one `e2-micro` VM, and an IAM binding granting `iap_ssh_accessor_email` access to tunnel to it. Nothing else. Type `yes` to confirm.

## 4. Wait, then verify

Give the VM 2–3 minutes after `apply` finishes for cloud-init to install Docker and bring up the stack. Then:

```bash
terraform output grafana_url
```

Open that URL, log in as `admin` with the password you set. The "Infrastructure Overview" dashboard is already provisioned.

**If it's not up after a few minutes**, the README has a step-by-step troubleshooting section (SSH in via `terraform output ssh_command`, check `cloud-init status`, check `docker compose ps`) — see `README.md` → "Verifying / troubleshooting a first apply".

## 5. What to check once it's live

- Grafana → Infrastructure Overview dashboard shows real data (CPU/memory/disk from node_exporter, per-container stats from cAdvisor).
- The "TLS & Security" panels show a valid cert expiry for both the external probe target and the stack's own `https://<ip>.sslip.io` endpoint.
- SSH in and run `sudo fail2ban-client status sshd` — should report the jail as active (this was a genuine bug fixed in this round of work; confirm it took effect on your real boot).
- If you set `alertmanager_webhook_url`, trigger a test alert (e.g. temporarily set `HighHostCPU`'s threshold low) and confirm the webhook fires. If you left it unset, confirm Alertmanager container is still healthy (`docker compose ps`) even with no receiver configured.

## 6. Test the IP-independent SSH paths

Two extra SSH paths exist alongside `ssh_source_ranges`, specifically so a home-IP change never locks you out again:

**IAP tunnel** (always available once applied, no VM-side setup needed):

```bash
gcloud compute ssh <ssh_user>@<instance_name> --zone=<zone> --tunnel-through-iap --project=<project_id>
```

This works only for the identity you set as `iap_ssh_accessor_email`. If it fails with a permission error, double-check `gcloud auth list` shows you're logged in as that exact account, and that `terraform apply` completed the `google_compute_instance_iam_member.iap_tunnel_accessor` resource.

**Tailscale** (only if you set `tailscale_auth_key`):

```bash
# SSH in via ssh_command or the IAP command above first, then:
tailscale status   # should show this device connected to your tailnet
tailscale ip -4    # note this address — it's stable regardless of the VM's public IP
```

From then on, `ssh <ssh_user>@<that-tailscale-ip>` works from any device also on your tailnet, independent of both the VM's public IP and your home IP.

## Teardown

```bash
cd terraform
terraform destroy
```

This does not disable the Compute Engine API on your project (`disable_on_destroy = false`) — that's a project-level setting other things may depend on.

---

For what's still manual/human-only beyond this, and ideas for what's next, see `NEXT_STEPS.md`.
