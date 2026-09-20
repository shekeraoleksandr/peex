# Runbook

One entry per alert. Each says what fired, what it usually means, how to
confirm, and what to do. Alert annotations link here by anchor.

Connect first:
```bash
cd ../../11-network/terraform
$(terraform output -raw ssh_monitoring)
cd ~/peex-observability
```

Useful everywhere:
```bash
sudo docker compose ps                      # what is running
sudo docker logs --tail 50 <container>      # one container's logs
curl -s localhost:9090/api/v1/alerts        # what Prometheus thinks is firing
curl -s localhost:5001/alerts               # what the webhook recorded
```

---

## ContainerHighCpu
**Fires:** a container used >0.8 cores for 2 minutes.

**Usually means:** a runaway loop, an unexpected workload spike, or a container
without a CPU limit on a 2-vCPU box.

**Confirm:**
```bash
sudo docker stats --no-stream
curl -sG localhost:9090/api/v1/query --data-urlencode \
  'query=topk(5, sum by (name) (rate(container_cpu_usage_seconds_total{name!=""}[2m])))'
```

**Do:** identify the container, check its logs for a retry storm. If it is
legitimate load, set an explicit `cpus:` limit in `docker-compose.yml` so one
container cannot starve the rest. If it is the demo stress container
(`peex_stress`), someone is running `trigger-alert.sh` — just remove it.

---

## ContainerHighMemory
**Fires:** a container is above 85% of its own memory limit for 3 minutes.

**Usually means:** a leak, or a limit set too low for real usage.

**Confirm:**
```bash
sudo docker stats --no-stream
curl -sG localhost:9090/api/v1/query --data-urlencode \
  'query=container_memory_usage_bytes{name!=""} / (container_spec_memory_limit_bytes{name!=""} > 0)'
```

**Do:** if usage climbs steadily and never drops, treat it as a leak and
restart the container to restore service, then investigate. If it plateaus just
under the limit, the limit is simply too small — raise it.

**Note:** this alert only evaluates containers that *have* a memory limit. The
`> 0` guard is deliberate; without it, unlimited containers divide by zero and
the alert fires permanently.

---

## ContainerRestarted
**Fires:** a container's start time changed within 10 minutes.

**Usually means:** a crash loop, an OOM kill, or a deliberate redeploy.

**Confirm:**
```bash
sudo docker ps -a --format 'table {{.Names}}\t{{.Status}}'
sudo docker inspect <container> --format '{{.State.ExitCode}} {{.State.OOMKilled}}'
sudo docker logs --tail 100 <container>
```

**Do:** `OOMKilled=true` means raise the memory limit or fix the leak. A
non-zero exit code with a config error in the logs means fix the config — the
container will keep restarting until you do. A single restart right after a
deploy is expected; close it.

---

## ContainerDisappeared
**Fires (critical):** cAdvisor has had no sample for a container in >60s.

**Usually means:** the container died and did not come back, or Docker itself
is unhealthy.

**Confirm:**
```bash
sudo docker ps -a | grep <name>
sudo systemctl status docker
```

**Do:** `docker compose up -d` brings back anything in the stack. If Docker
itself is down, restart it (`sudo systemctl restart docker`) and expect a burst
of resolved alerts afterwards. This alert inhibits that container's CPU/memory
alerts, so it is the one to act on.

---

## TargetDown
**Fires (critical):** Prometheus could not scrape a target for 2 minutes.

**Usually means:** the exporter is down, or — for `node-web` — the security
group or the web instance is the problem, not the exporter.

**Confirm:**
```bash
curl -s localhost:9090/api/v1/targets | python3 -m json.tool | grep -A3 lastError
# for the web instance specifically:
curl -sm 5 http://<web_private_ip>:9100/metrics | head -3
```

**Do:** if the web instance's node-exporter is unreachable but the instance is
up, check that the SG rule allowing 9100 from the monitoring SG still exists
(`11-network/terraform/security-groups.tf`). A `terraform apply` in that stack
restores it.

---

## HostHighMemory
**Fires:** less than 10% memory available for 5 minutes.

**Confirm:** `free -h`, then `sudo docker stats --no-stream` to find the
consumer.

**Do:** on a t3.micro (1GB) the whole stack is close to the ceiling by design.
If this fires steadily rather than in spikes, the instance is undersized —
move to `t3.small` by changing `instance_type` in `11-network`, or drop a
component you are not using.

---

## HostDiskFilling
**Fires:** root filesystem above 85% for 5 minutes.

**Usually means:** Prometheus TSDB or Loki chunks growing.

**Confirm:**
```bash
df -h /
sudo du -sh /var/lib/docker/volumes/* | sort -rh | head
```

**Do:** retention is already capped (Prometheus 7d/2GB, Loki 7d). If it still
fills, lower `--storage.tsdb.retention.size` in `docker-compose.yml` and
recreate the container. `docker system prune -f` reclaims dead images and is
safe here.

---

## EndpointDown
**Fires (critical):** blackbox got no 2xx from a probed URL for 2 minutes.

**Confirm:**
```bash
curl -sI http://<web_private_ip>/
sudo docker logs --tail 30 peex_blackbox
```

**Do:** this is the user-visible one — treat it first. If nginx on the web
instance is down, `sudo systemctl restart nginx` there. If blackbox itself is
the problem, the metric would be missing rather than 0, and `TargetDown` fires
instead.

---

## EndpointSlow
**Fires:** probe latency above 2s for 3 minutes.

**Do:** correlate with `ContainerHighCpu` and `HostHighMemory` on the same
timeline in Grafana — slow responses on a small instance are almost always
resource starvation rather than application logic. If the host is idle, look at
the application.

---

## DemoStressAlert
**Fires:** the `peex_stress` container is burning CPU.

**This is not a production alert.** It exists so `scripts/trigger-alert.sh` can
demonstrate the full alert path on demand. If it fires unexpectedly, someone
left the stress container running:
```bash
sudo docker rm -f peex_stress
```

---

## CloudWatch: `peex-containers-monitoring-status-check-failed`
**Fires:** EC2 status checks failed — the instance or its network is unhealthy.

Arrives by e-mail via SNS, independently of everything above, because when this
fires the in-instance Prometheus stack is usually down too.

**Do:** check the instance in the EC2 console. A failed *system* status check is
AWS-side (stop/start migrates to new hardware); a failed *instance* status check
is usually the OS. Nothing in this repo can fix it from inside.
