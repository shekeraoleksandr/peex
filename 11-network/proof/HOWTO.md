# How to fill this folder

`proof/` is empty in the kit — the live evidence needs a real AWS account
(VPC, EC2, security groups), which is exactly what `terraform apply` creates.

Easiest — from the machine where your `aws` CLI is logged in:
```bash
cd scripts
./apply.sh            # terraform init/plan/apply, waits for cloud-init,
                       # then runs collect-proof.sh automatically
```

Or step by step:
```bash
cd terraform
terraform init
TF_VAR_allowed_cidr="$(../scripts/get-my-ip.sh)" terraform apply
cd ../scripts
./collect-proof.sh    # -> proof/00_network_compute_observability_proof.txt
```

Artifacts map to the PeEx "Outcome Artifacts" across all three competencies:

| Competency | Artifact required | Where in proof |
|---|---|---|
| Network | VPC/subnet/routing configuration | `00_..._proof.txt` (VPC/subnet/route table section) |
| Network | Firewall rules (least privilege) | `00_..._proof.txt` (security groups section) — note the internet-facing rules are scoped to your IP, and node_exporter (9100) is proven unreachable from the internet |
| Compute | Provision VM (predefined type + image) | `00_..._proof.txt` (EC2 instances section) + `05-compute/proof/` |
| Compute | Verify access / OS configuration | `05-compute/proof/00_compute_proof.txt` (SSH session, nginx enabled+active) |
| Compute | Monitor VM resource usage | `05-compute/proof/00_compute_proof.txt` (uptime/memory/disk + node_exporter) |
| Observability | Infrastructure monitoring (Junior, KEY) | `00_..._proof.txt` (Prometheus targets UP, Grafana health) — real hosted stack, complements the local docker-compose stack in `04-observability/` |

Add a screenshot of the Grafana dashboard (`http://<monitoring-ip>:3000`) or
the AWS VPC console if the reviewer wants visuals.

**Remember to run `../scripts/destroy.sh` when you're done demoing** — two
running EC2 instances aren't free-tier forever.
