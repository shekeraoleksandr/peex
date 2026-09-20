# How to fill this folder

Locally (Python 3 required; no CI service needed):
```bash
./pipeline/run-local.sh              | tee proof/01_pipeline_run.txt
./pipeline/update-config.sh 1.1.0 production | tee proof/02_update_config.txt
./pipeline/run-local.sh              | tee -a proof/02_update_config.txt   # redeploy new version
./pipeline/verify-results.sh         | tee proof/03_verify_results.txt
```

On a real CI service (optional, stronger): push the folder as a repo and add a
screenshot of the successful GitHub Actions run or GitLab pipeline (stages
green, artifacts present).

| Item | Proof |
|------|-------|
| Update configuration files | 02_update_config.txt |
| Deploy a pre-configured application | 01_pipeline_run.txt (deploy stage) |
| Verify CI/CD pipeline execution results | 03_verify_results.txt |
