#!/usr/bin/env bash
# Deploys the API to Google Cloud Run. Cloud Build builds this folder's
# Dockerfile, so no local Docker is needed.
#
#   ./deploy.sh --setup   first time, or after a key in .env changes: enables the
#                         APIs, creates the runtime service account, copies
#                         GEMINI_API_KEY, MONGODB_URI and ADMIN_API_KEY from .env
#                         into Secret Manager, then deploys
#   ./deploy.sh           every later release: builds and rolls out a new revision
#
# Needs the gcloud CLI signed in (gcloud auth login) to a project with billing
# enabled, and MongoDB Atlas allowing 0.0.0.0/0 (Cloud Run has no fixed IP).
# Any variable below can be overridden: PROJECT_ID=my-project ./deploy.sh
#
# On a project where --setup has just enabled Cloud Run, the first build fails
# with PERMISSION_DENIED for a few minutes while the default build account it
# creates gets its role. Run ./deploy.sh again a few minutes later.
set -euo pipefail
cd "$(dirname "$0")"

# The app's Firebase project, named here rather than read from gcloud's config,
# so a gcloud pointed at another project cannot deploy there by accident.
PROJECT_ID="${PROJECT_ID:-fir-auth-login-udacity}"
REGION="${REGION:-asia-southeast1}"
SERVICE="${SERVICE:-smartfin-api}"
DB_NAME="${DB_NAME:-smartfin}"
# Caps cost, and what an unauthenticated public API can be made to spend.
MAX_INSTANCES="${MAX_INSTANCES:-2}"
RUNTIME_SA="smartfin-api@${PROJECT_ID}.iam.gserviceaccount.com"

# Environment variable : Secret Manager secret. The prefix keeps them apart from
# other secrets in the project (Firebase Functions also stores its secrets there).
SECRETS="GEMINI_API_KEY:smartfin-gemini-api-key MONGODB_URI:smartfin-mongodb-uri ADMIN_API_KEY:smartfin-admin-api-key"

# The value of $1 in .env without surrounding quotes. Never printed.
env_value() {
  local v
  v=$(sed -n "s/^$1=//p" .env | tail -n 1 | tr -d '\r')
  v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
  printf '%s' "$v"
}

# A service account just created can take a few seconds to become usable in IAM.
retry() {
  local attempt
  for attempt in 1 2 3 4 5 6; do
    "$@" && return 0
    sleep 5
  done
  return 1
}

setup() {
  [ -f .env ] || { echo ".env not found: --setup copies the secrets from it." >&2; exit 1; }

  echo "==> Enabling APIs on $PROJECT_ID"
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
    artifactregistry.googleapis.com secretmanager.googleapis.com iam.googleapis.com \
    --project "$PROJECT_ID"

  if ! gcloud iam service-accounts describe "$RUNTIME_SA" --project "$PROJECT_ID" >/dev/null 2>&1; then
    echo "==> Creating runtime service account $RUNTIME_SA"
    gcloud iam service-accounts create smartfin-api --project "$PROJECT_ID" \
      --display-name "SmartFin API (Cloud Run)"
  fi

  echo "==> Copying secrets from .env into Secret Manager"
  local pair var secret value
  for pair in $SECRETS; do
    var="${pair%%:*}"; secret="${pair#*:}"
    value=$(env_value "$var")
    [ -n "$value" ] || { echo "$var is empty in .env" >&2; exit 1; }
    if ! gcloud secrets describe "$secret" --project "$PROJECT_ID" >/dev/null 2>&1; then
      gcloud secrets create "$secret" --project "$PROJECT_ID" --replication-policy automatic
    fi
    # Through stdin, so the value never appears in a process listing.
    printf '%s' "$value" | gcloud secrets versions add "$secret" --project "$PROJECT_ID" --data-file=-
    # The service can read these three secrets and nothing else in the project.
    retry gcloud secrets add-iam-policy-binding "$secret" --project "$PROJECT_ID" \
      --member "serviceAccount:$RUNTIME_SA" --role roles/secretmanager.secretAccessor >/dev/null
    echo "    $var -> $secret"
  done
}

deploy() {
  local secret_flags="" pair url
  for pair in $SECRETS; do
    secret_flags="${secret_flags:+$secret_flags,}${pair%%:*}=${pair#*:}:latest"
  done

  # --timeout stays above the coach's 45s budget; PORT is set by Cloud Run.
  echo "==> Deploying $SERVICE to $REGION ($PROJECT_ID)"
  gcloud run deploy "$SERVICE" --project "$PROJECT_ID" --region "$REGION" \
    --source . --quiet \
    --service-account "$RUNTIME_SA" \
    --allow-unauthenticated \
    --set-env-vars "DB_NAME=$DB_NAME" \
    --set-secrets "$secret_flags" \
    --max-instances "$MAX_INSTANCES" \
    --timeout 120

  url=$(gcloud run services describe "$SERVICE" --project "$PROJECT_ID" --region "$REGION" \
    --format 'value(status.url)')
  echo "==> Live at $url"
  curl -fsS "$url/health" && echo
}

case "${1:-}" in
  --setup) setup ;;
  "") ;;
  *) echo "usage: ./deploy.sh [--setup]" >&2; exit 1 ;;
esac
deploy
