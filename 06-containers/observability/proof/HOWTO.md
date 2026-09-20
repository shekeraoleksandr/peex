# How to fill this folder

Requires the `11-network` stack to be up (it owns the EC2 instances), plus
`gcloud` logged in for the GCP half.

```bash
./scripts/deploy.sh               # stack onto the monitoring instance
./scripts/collect-proof.sh        # -> 01_observability_proof.txt
./scripts/gcp-export.sh           # -> 02_gcp_cloudrun_observability.txt
cd terraform && terraform apply -var="alert_email=<you>"   # email channel
cd .. && ./scripts/trigger-alert.sh stress                 # -> 03_triggered_alert_stress.txt
```

Artifacts map to the NEBO task's "Outcome Artifacts":

| Artifact required | Where |
|---|---|
| Monitoring stack deployment configuration | `docker-compose.yml`, `prometheus/`, `loki/`, `promtail/`, `alertmanager/`, `grafana/`, `terraform/` |
| Dashboards showing container metrics | `grafana/.../containers.json`; screenshot Grafana + the GCP dashboard exported to `gcp-export/` |
| Log aggregation showing centralized logs | `01_observability_proof.txt` §5 (Loki labels, container list, live query); Grafana "Container logs" panel |
| Alert rule configurations with thresholds | `prometheus/alert.rules.yml`; `01_observability_proof.txt` §6 lists them as loaded |
| Triggered alerts and notifications | `03_triggered_alert_*.txt` (Prometheus firing → Alertmanager → webhook record); the SNS e-mail for the CloudWatch path |
| Example queries for metrics and logs | `README.md` demo section, and §3–§5 of the proof |
| Documentation of monitoring architecture | `docs/architecture.md` |
| Short README (components, dashboards, alerts, troubleshooting) | `README.md` + `docs/runbook.md` |

## Screenshots worth taking
- Grafana → **PeEx — Container Observability** with data flowing (per-container
  CPU/memory panels populated).
- Prometheus → **Alerts** page showing the rules, with one firing during
  `trigger-alert.sh`.
- Alertmanager (over the tunnel, `localhost:9093`) showing the live incident.
- The **SNS e-mail** in your inbox (the notification-channel artifact).
- GCP → Cloud Monitoring → your four-golden-signals dashboard.
- GCP → Logs Explorer filtered to `resource.type=cloud_run_revision`.
