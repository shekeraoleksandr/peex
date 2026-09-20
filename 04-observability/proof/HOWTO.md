# How to fill this folder

Two parts:

## 1. Offline (no Docker) — already runnable anywhere
```bash
./scripts/log-summary.sh > proof/01_log_summary.txt
```
(`docs/observability-data-types.md` is itself the artifact for the
"identify observability data types" item.)

## 2. Live stack (where Docker is available: Mac with Docker Desktop, or a cloud VM)
```bash
docker compose up -d
sleep 30
./scripts/collect-proof.sh          # -> proof/observability_proof.txt
```
