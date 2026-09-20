#!/usr/bin/env bash
# Prove the images live in a real container registry (GCP Artifact Registry),
# pushed by the project's own Cloud Build / GitHub Actions pipelines.
# Nothing is pushed here -- this reads what is already published.
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
require gcloud

{
echo "### CONTAINER REGISTRY @ $(date -u '+%F %T UTC')"
echo "project=$GCP_PROJECT  region=$GCP_REGION  host=$GAR_HOST"

note "gcloud auth list"
gcloud auth list 2>&1 || true

note "gcloud artifacts repositories list --project $GCP_PROJECT --location $GCP_REGION"
gcloud artifacts repositories list --project "$GCP_PROJECT" --location "$GCP_REGION" 2>&1 || true

note "gcloud artifacts docker images list $GAR_LANDING_URI --include-tags --limit 10"
gcloud artifacts docker images list "$GAR_LANDING_URI" \
    --include-tags --limit 10 --sort-by=~UPDATE_TIME 2>&1 || true

note "gcloud artifacts docker images list $GAR_FUNCTIONS_URI --include-tags --limit 20"
gcloud artifacts docker images list "$GAR_FUNCTIONS_URI" \
    --include-tags --limit 20 --sort-by=~UPDATE_TIME 2>&1 || true

echo
echo "-- the pipelines that push these images (the real 'docker push' step) --"

note "sed -n '1,30p' \$MOVIELINKS/movielinksParser/infra/cloudbuild/tastefilter/cloudbuild.yaml"
sed -n '1,30p' "$MOVIELINKS/movielinksParser/infra/cloudbuild/tastefilter/cloudbuild.yaml" 2>&1 || true

note "gcloud builds list --project $GCP_PROJECT --limit 10"
gcloud builds list --project "$GCP_PROJECT" --limit 10 2>&1 || true

echo
echo "REGISTRY LISTING DONE"
} 2>&1 | tee "$PROOF/04_registry.txt"
echo "==> Wrote $PROOF/04_registry.txt"
