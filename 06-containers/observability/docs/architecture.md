# Monitoring architecture

Two environments, monitored by two independent mechanisms each, so no single
component's failure blinds the whole system.

```
ENVIRONMENT A — containers on a VM instance (AWS, built in 11-network)
┌──────────────────────────── EC2: monitoring (t3.micro) ─────────────────────────────┐
│                                                                                      │
│   cAdvisor ─────────┐         (per-container cpu/mem/net/disk)                       │
│   node-exporter ────┤                                                                │
│   blackbox ─────────┼──scrape──► Prometheus ──evaluate rules──► Alertmanager         │
│        │            │             │  7d / 2GB retention            │                 │
│        │            │             │                                ├─► webhook-sink  │
│   (probes)          │             └──query──► Grafana              │   (automated    │
│        │            │                          │                   │    action, logs │
│        │        promtail ──ship──► Loki ───────┘                   │    every alert) │
│        │         (docker sd,        7d retention                   │                 │
│        │          secrets redacted)                                └─► (email: see   │
│        │                                                                terraform/)  │
└────────┼─────────────────────────────────────────────────────────────────────────────┘
         │ private VPC IP, SG-restricted (9100 open only to this SG)
         ▼
┌─────────── EC2: web ───────────┐
│  nginx  +  node-exporter        │
└─────────────────────────────────┘

         ┌──────────── independent of the box above ────────────┐
         │  AWS CloudWatch alarms ──► SNS topic ──► e-mail      │
         │  (EC2 CPU + StatusCheckFailed on BOTH instances)     │
         └──────────────────────────────────────────────────────┘

ENVIRONMENT B — containers on Container Apps (GCP Cloud Run, ~10 services)
┌──────────────────────────────────────────────────────────────────────────┐
│  Cloud Run services ──► Cloud Monitoring (four golden signals dashboard) │
│           │                                                              │
│           └──────────► Cloud Logging (centralized, automatic per service)│
└──────────────────────────────────────────────────────────────────────────┘
```

## Why two mechanisms per environment

The Prometheus stack runs *on* the instance it monitors. That is fine for
container-level detail, but it structurally cannot alert on its own death — if
the box goes down, so does the thing that would have told you. CloudWatch
alarms plus SNS live outside the instance and cover exactly that gap
(`StatusCheckFailed`), and they deliver to e-mail without any SMTP credentials
sitting on disk.

The same reasoning applies on GCP: Cloud Monitoring and Cloud Logging are
managed by the platform, not by the containers being observed.

## Signal coverage

| Signal | Where it comes from | Alert |
|---|---|---|
| Container CPU | cAdvisor `container_cpu_usage_seconds_total` | `ContainerHighCpu` (>0.8 cores, 2m) |
| Container memory | cAdvisor `container_memory_usage_bytes` vs limit | `ContainerHighMemory` (>85%, 3m) |
| Container network | cAdvisor `container_network_*_bytes_total` | dashboard only |
| Container restart | cAdvisor `container_start_time_seconds` | `ContainerRestarted` |
| Container death | cAdvisor `container_last_seen` | `ContainerDisappeared` (critical) |
| Readiness / liveness | blackbox `probe_success` | `EndpointDown` (critical) |
| Latency | blackbox `probe_duration_seconds` | `EndpointSlow` (>2s, 3m) |
| Scrape health | Prometheus `up` | `TargetDown` (critical) |
| Host memory / disk | node-exporter | `HostHighMemory`, `HostDiskFilling` |
| Host / instance death | CloudWatch `StatusCheckFailed` | SNS e-mail |
| Container logs | Promtail → Loki | queried in Grafana |
| Cloud Run metrics + logs | Cloud Monitoring / Cloud Logging | existing dashboard |

## Deliberate design decisions

**Exposure.** Only Prometheus (9090) and Grafana (3000) are published, and only
to `allowed_cidr`. Alertmanager, cAdvisor and Loki bind to `127.0.0.1` and are
reached over an SSH tunnel. Adding six more internet-facing ports to see a few
dashboards would be a poor trade.

**Retention.** Prometheus is capped at 7 days / 2GB and Loki at 7 days. This is
a t3.micro with one root volume; unbounded TSDB and log growth would fill it,
which is why `HostDiskFilling` exists as a backstop.

**Secrets in logs.** Promtail redacts password/token/secret/api-key patterns,
`Bearer` tokens and e-mail addresses in a pipeline stage — at ingest, before
anything is written to Loki. Redacting at query time would be too late.

**Alert noise.** `repeat_interval` is 4h (1h for critical), and two inhibition
rules suppress derived alerts: a disappeared container silences its own
CPU/memory alerts, and a down scrape target silences warnings derived from it.

## Known gap

Kubernetes is not covered. The containerized workloads here run on Cloud Run
(Container Apps) and directly on a VM instance; there is no GKE/EKS/AKS cluster
in either project, so the K8s-specific outcome is out of scope rather than
faked with a throwaway cluster.
