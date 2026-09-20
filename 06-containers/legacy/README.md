# 06 — DevOps · Containers

Reproducible proof for the competency items marked **Yes** in PeEx
(**DevOps · Containers**), built around one small custom app image.

| Level  | Competency item                                   | Covered by |
|--------|---------------------------------------------------|------------|
| Trainee (KEY) | Build and run a basic container image             | `Dockerfile`, `scripts/build.sh`, `scripts/run.sh` |
| Trainee (KEY) | Update configuration for a containerized application | `config/app.env`, `scripts/update-config.sh` |
| Junior (KEY)  | Create and publish a custom container image       | `scripts/publish-ecr.sh` (Amazon ECR) |
| Middle        | Apply observability practices to containerized infra | `Dockerfile` HEALTHCHECK, `docker-compose.yml`, `scripts/observe.sh` |

## The app
A dependency-free (stdlib Python) HTTP service in `app/app.py`:
- `/` — status page whose content is driven entirely by **env config**;
- `/healthz` — liveness probe (used by the container HEALTHCHECK);
- `/metrics` — Prometheus-format metrics;
- structured **JSON logs** to stdout.

## Container practices baked in
- **Non-root** user (`appuser`), least privilege.
- **HEALTHCHECK** in the image and in compose.
- **Resource limits** (0.5 CPU / 128M) and **log rotation** in compose.
- 12-factor **config via environment** — change config without rebuilding.

## Run it (where Docker is available: Mac with Docker Desktop, or a VM)
```bash
./scripts/build.sh          # build a basic image           (Trainee)
./scripts/run.sh            # run it, verify it serves        (Trainee)
./scripts/observe.sh        # health, stats, logs, /metrics   (Middle)
./scripts/update-config.sh  # change env config & redeploy    (Trainee)
./scripts/publish-ecr.sh    # push to private ECR registry    (Junior)
# one-shot capture of everything (except publish):
./scripts/collect-proof.sh
# cleanup:
docker rm -f peex_app
```

Or with compose:
```bash
docker compose up -d --build
docker compose ps          # shows health
docker compose logs app
```

## Publish target
`publish-ecr.sh` pushes to **Amazon ECR** (private) using your logged-in aws
CLI (region us-east-1) — no extra registry credentials needed. To use Docker
Hub instead: `docker login`, then
`docker tag peex-app:1.0.0 <user>/peex-app:1.0.0 && docker push <user>/peex-app:1.0.0`.

## Evidence (proof/)
- `01_build.txt` — image built, non-root user + healthcheck present.
- `02_run.txt` — container running, HTTP 200 on `/` and `/healthz`.
- `03_observe.txt` — health status, `docker stats`, JSON logs, `/metrics`.
- `04_update_config.txt` — before/after showing config change without rebuild.
- `05_publish.txt` (optional) — image pushed, `ecr describe-images` listing it.

> Docker can't run in the assistant's sandboxes, so **you run these** where
> Docker is available. The app logic, endpoints and config mechanism were
> verified live (running `app/app.py` directly) during the build.
