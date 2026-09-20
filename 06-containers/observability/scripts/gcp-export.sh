#!/usr/bin/env bash
# READ-ONLY export of the second environment: the ~10 containerized services
# running on Google Cloud Run, monitored by Cloud Monitoring + Cloud Logging.
# Nothing is created or modified in GCP -- this captures what already exists
# and turns the clicked-together dashboard into a versioned artifact.
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
require gcloud

GCP_PROJECT="${GCP_PROJECT:-movielinks-475222}"
GCP_REGION="${GCP_REGION:-europe-west1}"
EXPORT_DIR="$ROOT/gcp-export"
mkdir -p "$EXPORT_DIR"

{
echo "### GCP CLOUD RUN OBSERVABILITY (read-only export) @ $(date -u '+%F %T UTC')"
echo "project=$GCP_PROJECT  region=$GCP_REGION"

echo
echo "===== Containerized workloads under observation (Cloud Run) ====="
note "gcloud run services list --project $GCP_PROJECT --region $GCP_REGION"
gcloud run services list --project "$GCP_PROJECT" --region "$GCP_REGION" 2>&1 || true

echo
echo "===== Dashboards defined in Cloud Monitoring ====="
note "gcloud monitoring dashboards list --project $GCP_PROJECT"
gcloud monitoring dashboards list --project "$GCP_PROJECT" \
    --format="table(displayName, name)" 2>&1 || true

echo
echo "-- exporting each dashboard to gcp-export/ as versionable JSON --"
while read -r dash; do
    [ -z "$dash" ] && continue
    slug="$(basename "$dash")"
    if gcloud monitoring dashboards describe "$dash" --project "$GCP_PROJECT" \
        --format=json > "$EXPORT_DIR/dashboard-$slug.json" 2>/dev/null; then
        title="$(python3 -c "import json;print(json.load(open('$EXPORT_DIR/dashboard-$slug.json')).get('displayName','?'))" 2>/dev/null || echo '?')"
        echo "   saved gcp-export/dashboard-$slug.json   ($title)"
    fi
done < <(gcloud monitoring dashboards list --project "$GCP_PROJECT" --format="value(name)" 2>/dev/null)

echo
echo "===== Alert policies (if any) ====="
note "gcloud alpha monitoring policies list --project $GCP_PROJECT"
gcloud alpha monitoring policies list --project "$GCP_PROJECT" \
    --format="table(displayName, enabled, conditions[0].displayName)" 2>&1 \
    || echo "(none configured, or the alpha component is not installed)"

echo
echo "===== Notification channels ====="
note "gcloud alpha monitoring channels list --project $GCP_PROJECT"
gcloud alpha monitoring channels list --project "$GCP_PROJECT" \
    --format="table(displayName, type, enabled)" 2>&1 \
    || echo "(none configured)"

echo
echo "===== Log-based metrics ====="
note "gcloud logging metrics list --project $GCP_PROJECT"
gcloud logging metrics list --project "$GCP_PROJECT" 2>&1 || true

echo
echo "===== Centralized logging is live: recent Cloud Run logs ====="
note "gcloud logging read 'resource.type=cloud_run_revision' --limit 10"
gcloud logging read 'resource.type=cloud_run_revision' \
    --project "$GCP_PROJECT" --limit 10 \
    --format="table(timestamp, resource.labels.service_name, severity, textPayload)" 2>&1 || true

echo
echo "===== Example: error-severity logs across all services (log query) ====="
note "gcloud logging read 'resource.type=cloud_run_revision AND severity>=ERROR' --limit 5"
gcloud logging read 'resource.type=cloud_run_revision AND severity>=ERROR' \
    --project "$GCP_PROJECT" --limit 5 \
    --format="table(timestamp, resource.labels.service_name, severity)" 2>&1 \
    || echo "(no recent errors -- that's a good sign)"

echo
echo "EXPORT DONE -- dashboards saved under gcp-export/"
} 2>&1 | tee "$PROOF/02_gcp_cloudrun_observability.txt"

echo "==> Wrote $PROOF/02_gcp_cloudrun_observability.txt"
echo "==> Dashboard JSON: $EXPORT_DIR"
