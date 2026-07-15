#!/usr/bin/env bash
# =============================================================================
# SCRIPT DE LEVANTAMIENTO DE INFRAESTRUCTURA GCP — OPTIMIZADO PARA CLOUD SHELL
# =============================================================================
# Versión: 2.1 (corrige bugs de v2.0)
# Uso: ./levantamiento-gcp.sh [--project PROJECT_ID] [--all-projects] [--output-dir DIR]
# =============================================================================
# CAMBIOS v2.1: NAT por router, VPC Peering por red, SQL Backups por instancia,
# Vertex AI multi-región, KMS dinámico, PSC separado, _status.json, START_TIME fix
# =============================================================================

set -o pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

START_TIME=$(date +%s)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TIMESTAMP_FILE=$(date +"%Y%m%d_%H%M%S")
OUTPUT_DIR="${OUTPUT_DIR:-./levantamiento_gcp_${TIMESTAMP_FILE}}"
SPECIFIC_PROJECT=""
ERRORS=0
OK=0
ALL_PROJECTS=false

declare -A SERVICE_STATUS
declare -A SERVICE_COUNT
declare -A SERVICE_MSG

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

while [[ $# -gt 0 ]]; do
    case $1 in
        --project) SPECIFIC_PROJECT="$2"; shift 2 ;;
        --all-projects) ALL_PROJECTS=true; shift ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --help)
            echo "Uso: $0 [--project PROJECT_ID] [--all-projects] [--output-dir DIR]"
            echo "  --all-projects: analiza TODOS los proyectos accesibles"
            exit 0 ;;
        *) echo "Opción desconocida: $1"; exit 1 ;;
    esac
done

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()  { echo -e "${GREEN}[ OK ]${NC} $1"; ((OK++)) || true; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((ERRORS++)) || true; }

classify_error() {
    local errmsg="$1"
    if echo "$errmsg" | grep -qiE "permission_denied|does not have permission|forbidden|access.*denied"; then
        echo "sin_permiso"
    elif echo "$errmsg" | grep -qiE "service_disabled|has not been used|is disabled|api.*not enabled"; then
        echo "api_deshabilitada"
    elif echo "$errmsg" | grep -qiE "not found|404|does not exist"; then
        echo "no_encontrado"
    elif [[ -z "$errmsg" ]]; then
        echo "sin_recursos"
    else
        echo "error_otro"
    fi
}

gsafe() {
    local desc="$1"; shift
    local outfile="$1"; shift
    local key; key=$(basename "$outfile" .json)
    local stderr_file; stderr_file=$(mktemp)

    if timeout 30 "$@" --format=json > "$outfile" 2>"$stderr_file"; then
        if jq empty "$outfile" 2>/dev/null; then
            local count
            count=$(jq 'if type == "array" then length elif type == "object" then (keys | length) else 0 end' "$outfile" 2>/dev/null)
            ok "$desc ($count elementos)"
            SERVICE_STATUS[$key]="ok"
            SERVICE_COUNT[$key]="${count:-0}"
            rm -f "$stderr_file"
            return 0
        fi
    fi

    local errmsg; errmsg=$(tr '\n' ' ' < "$stderr_file" | head -c 300)
    rm -f "$stderr_file"
    echo "[]" > "$outfile"
    local reason; reason=$(classify_error "$errmsg")
    case "$reason" in
        sin_permiso)       warn "$desc (SIN PERMISO)" ;;
        api_deshabilitada) warn "$desc (API DESHABILITADA)" ;;
        no_encontrado)     warn "$desc (no encontrado)" ;;
        *)                 warn "$desc (sin datos o timeout)" ;;
    esac
    SERVICE_STATUS[$key]="$reason"
    SERVICE_COUNT[$key]=0
    SERVICE_MSG[$key]="$errmsg"
    return 1
}

csafe() {
    local desc="$1"; shift
    local outfile="$1"; shift
    local key; key=$(basename "$outfile" .json)
    local stderr_file; stderr_file=$(mktemp)

    if timeout 30 "$@" > "$outfile" 2>"$stderr_file"; then
        if [[ -s "$outfile" ]]; then
            ok "$desc"
            SERVICE_STATUS[$key]="ok"
            rm -f "$stderr_file"
            return 0
        fi
    fi

    local errmsg; errmsg=$(tr '\n' ' ' < "$stderr_file" | head -c 300)
    rm -f "$stderr_file"
    echo "[]" > "$outfile"
    local reason; reason=$(classify_error "$errmsg")
    warn "$desc ($reason)"
    SERVICE_STATUS[$key]="$reason"
    SERVICE_MSG[$key]="$errmsg"
    return 1
}

# =============================================================================
# VERIFICACIÓN INICIAL
# =============================================================================

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   LEVANTAMIENTO GCP v2.1 — Optimizado para Cloud Shell      ║${NC}"
echo -e "${CYAN}║   Solo lectura | Costo: \$0 | Escribe a disco progresivo     ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

command -v gcloud &>/dev/null || { fail "gcloud no encontrado"; exit 1; }
command -v jq &>/dev/null || { fail "jq no encontrado"; exit 1; }

ACCOUNT=$(gcloud config get-value account 2>/dev/null)
[[ -z "$ACCOUNT" || "$ACCOUNT" == "(unset)" ]] && { fail "No autenticado"; exit 1; }

if [[ "$ALL_PROJECTS" == true ]]; then
    log "Modo: TODOS los proyectos accesibles"
    PROJECT_LIST=$(gcloud projects list --format="value(projectId)" 2>/dev/null)
    PROJECT_COUNT=$(echo "$PROJECT_LIST" | grep -c .)
    [[ $PROJECT_COUNT -eq 0 ]] && { fail "No se encontraron proyectos"; exit 1; }

    echo -e "  Cuenta:    ${GREEN}$ACCOUNT${NC}"
    echo -e "  Proyectos: ${GREEN}$PROJECT_COUNT${NC}"
    echo ""
    echo "$PROJECT_LIST" | while read -r p; do echo "    • $p"; done
    echo ""

    mkdir -p "$OUTPUT_DIR"
    CURRENT=0
    echo "$PROJECT_LIST" | while IFS= read -r PROJECT; do
        [[ -z "$PROJECT" ]] && continue
        ((CURRENT++)) || true
        echo ""
        echo -e "${CYAN}══ PROYECTO [$CURRENT/$PROJECT_COUNT]: $PROJECT ══${NC}"
        PROJECT_DIR="$OUTPUT_DIR/$PROJECT"
        mkdir -p "$PROJECT_DIR"
        bash "$0" --project "$PROJECT" --output-dir "$PROJECT_DIR"
    done

    echo ""
    echo -e "${GREEN}✓ Multi-proyecto completado. Output: $OUTPUT_DIR/${NC}"
    echo -e "  tar czf levantamiento_gcp.tar.gz $OUTPUT_DIR/"
    exit 0
fi

# Modo proyecto único
if [[ -n "$SPECIFIC_PROJECT" ]]; then
    PROJECT="$SPECIFIC_PROJECT"
else
    PROJECT=$(gcloud config get-value project 2>/dev/null)
fi
[[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]] && { fail "Sin proyecto. Usar --project o --all-projects"; exit 1; }

mkdir -p "$OUTPUT_DIR"
echo -e "  Cuenta:   ${GREEN}$ACCOUNT${NC}"
echo -e "  Proyecto: ${GREEN}$PROJECT${NC}"
echo -e "  Output:   ${GREEN}$OUTPUT_DIR/${NC}"
echo ""

cat > "$OUTPUT_DIR/_metadata.json" << EOF
{"timestamp":"$TIMESTAMP","account":"$ACCOUNT","project":"$PROJECT","gcloud_version":"$(gcloud version 2>/dev/null | head -1)","script_version":"2.1-cloudshell"}
EOF

# =============================================================================
# RECOPILACIÓN
# =============================================================================

echo -e "${CYAN}━━━ IAM ━━━${NC}"
gsafe "IAM Policy" "$OUTPUT_DIR/iam_policy.json" gcloud projects get-iam-policy "$PROJECT"
gsafe "Service Accounts" "$OUTPUT_DIR/iam_service_accounts.json" gcloud iam service-accounts list --project="$PROJECT"
gsafe "Custom Roles" "$OUTPUT_DIR/iam_custom_roles.json" gcloud iam roles list --project="$PROJECT"

log "Recopilando SA Keys (metadata)..."
SA_KEYS_FILE="$OUTPUT_DIR/iam_sa_keys.json"
echo "[" > "$SA_KEYS_FILE"
first=true
while IFS= read -r sa_email; do
    [[ -z "$sa_email" ]] && continue
    keys=$(gcloud iam service-accounts keys list --iam-account="$sa_email" --project="$PROJECT" --format=json 2>/dev/null)
    if [[ -n "$keys" && "$keys" != "[]" ]]; then
        $first || echo "," >> "$SA_KEYS_FILE"
        echo "{\"service_account\": \"$sa_email\", \"keys\": $keys}" >> "$SA_KEYS_FILE"
        first=false
    fi
done < <(gcloud iam service-accounts list --project="$PROJECT" --format="value(email)" 2>/dev/null)
echo "]" >> "$SA_KEYS_FILE"
ok "SA Keys"

echo ""
echo -e "${CYAN}━━━ COMPUTE ENGINE ━━━${NC}"
gsafe "Instances" "$OUTPUT_DIR/compute_instances.json" gcloud compute instances list --project="$PROJECT"
gsafe "Instance Templates" "$OUTPUT_DIR/compute_templates.json" gcloud compute instance-templates list --project="$PROJECT"
gsafe "MIGs" "$OUTPUT_DIR/compute_migs.json" gcloud compute instance-groups managed list --project="$PROJECT"
gsafe "Disks" "$OUTPUT_DIR/compute_disks.json" gcloud compute disks list --project="$PROJECT"
gsafe "Snapshots" "$OUTPUT_DIR/compute_snapshots.json" gcloud compute snapshots list --project="$PROJECT"
gsafe "Images (custom)" "$OUTPUT_DIR/compute_images.json" gcloud compute images list --project="$PROJECT" --no-standard-images
gsafe "Machine Images" "$OUTPUT_DIR/compute_machine_images.json" gcloud compute machine-images list --project="$PROJECT"
gsafe "Reservations" "$OUTPUT_DIR/compute_reservations.json" gcloud compute reservations list --project="$PROJECT"

echo ""
echo -e "${CYAN}━━━ GKE ━━━${NC}"
gsafe "GKE Clusters" "$OUTPUT_DIR/gke_clusters.json" gcloud container clusters list --project="$PROJECT"
log "Node pools por cluster..."
NP_FILE="$OUTPUT_DIR/gke_nodepools.json"
echo "[" > "$NP_FILE"
first=true
while IFS=$'\t' read -r cname zone; do
    [[ -z "$cname" ]] && continue
    pools=$(gcloud container node-pools list --cluster="$cname" --location="$zone" --project="$PROJECT" --format=json 2>/dev/null)
    if [[ -n "$pools" && "$pools" != "[]" ]]; then
        $first || echo "," >> "$NP_FILE"
        echo "{\"cluster\":\"$cname\",\"location\":\"$zone\",\"node_pools\":$pools}" >> "$NP_FILE"
        first=false
    fi
done < <(gcloud container clusters list --project="$PROJECT" --format="value(name,location)" 2>/dev/null)
echo "]" >> "$NP_FILE"
ok "GKE Node Pools"

echo ""
echo -e "${CYAN}━━━ CLOUD RUN / FUNCTIONS / APP ENGINE ━━━${NC}"
gsafe "Cloud Run Services" "$OUTPUT_DIR/cloudrun_services.json" gcloud run services list --project="$PROJECT" --platform=managed
gsafe "Cloud Run Jobs" "$OUTPUT_DIR/cloudrun_jobs.json" gcloud run jobs list --project="$PROJECT"
gsafe "Cloud Functions" "$OUTPUT_DIR/functions.json" gcloud functions list --project="$PROJECT" --gen2
gsafe "App Engine App" "$OUTPUT_DIR/appengine_app.json" gcloud app describe --project="$PROJECT"
gsafe "App Engine Services" "$OUTPUT_DIR/appengine_services.json" gcloud app services list --project="$PROJECT"

echo ""
echo -e "${CYAN}━━━ VPC / NETWORKING ━━━${NC}"
gsafe "VPC Networks" "$OUTPUT_DIR/vpc_networks.json" gcloud compute networks list --project="$PROJECT"
gsafe "Subnets" "$OUTPUT_DIR/vpc_subnets.json" gcloud compute networks subnets list --project="$PROJECT"
gsafe "Firewall Rules" "$OUTPUT_DIR/vpc_firewall_rules.json" gcloud compute firewall-rules list --project="$PROJECT"
gsafe "Routes" "$OUTPUT_DIR/vpc_routes.json" gcloud compute routes list --project="$PROJECT"
gsafe "Routers" "$OUTPUT_DIR/vpc_routers.json" gcloud compute routers list --project="$PROJECT"

# NAT: iterar por router (fix v2.1)
log "NAT Gateways por router..."
NAT_FILE="$OUTPUT_DIR/vpc_nat.json"
echo "[" > "$NAT_FILE"
first=true
while IFS=$'\t' read -r rname rregion; do
    [[ -z "$rname" ]] && continue
    nats=$(gcloud compute routers nats list --router="$rname" --region="$rregion" --project="$PROJECT" --format=json 2>/dev/null)
    if [[ -n "$nats" && "$nats" != "[]" ]]; then
        $first || echo "," >> "$NAT_FILE"
        echo "{\"router\":\"$rname\",\"region\":\"$rregion\",\"nats\":$nats}" >> "$NAT_FILE"
        first=false
    fi
done < <(gcloud compute routers list --project="$PROJECT" --format="value(name,region.basename())" 2>/dev/null)
echo "]" >> "$NAT_FILE"
ok "NAT Gateways"

gsafe "VPN Tunnels" "$OUTPUT_DIR/vpc_vpn_tunnels.json" gcloud compute vpn-tunnels list --project="$PROJECT"
gsafe "VPN Gateways" "$OUTPUT_DIR/vpc_vpn_gateways.json" gcloud compute vpn-gateways list --project="$PROJECT"
gsafe "Interconnects" "$OUTPUT_DIR/vpc_interconnects.json" gcloud compute interconnects list --project="$PROJECT"
gsafe "External IPs" "$OUTPUT_DIR/vpc_external_ips.json" gcloud compute addresses list --project="$PROJECT"

# VPC Peering: iterar todas las redes (fix v2.1)
log "VPC Peering por red..."
PEER_FILE="$OUTPUT_DIR/vpc_peering.json"
echo "[" > "$PEER_FILE"
first=true
while IFS= read -r net_name; do
    [[ -z "$net_name" ]] && continue
    peerings=$(gcloud compute networks peerings list --project="$PROJECT" --network="$net_name" --format=json 2>/dev/null)
    if [[ -n "$peerings" && "$peerings" != "[]" ]]; then
        $first || echo "," >> "$PEER_FILE"
        echo "{\"network\":\"$net_name\",\"peerings\":$peerings}" >> "$PEER_FILE"
        first=false
    fi
done < <(gcloud compute networks list --project="$PROJECT" --format="value(name)" 2>/dev/null)
echo "]" >> "$PEER_FILE"
ok "VPC Peering"

echo ""
echo -e "${CYAN}━━━ PRIVATE SERVICE CONNECT ━━━${NC}"
gsafe "PSC Endpoints (consumidor)" "$OUTPUT_DIR/psc_endpoints_consumer.json" gcloud compute addresses list --project="$PROJECT" --filter="purpose=PRIVATE_SERVICE_CONNECT"
gsafe "PSC Service Attachments" "$OUTPUT_DIR/psc_service_attachments.json" gcloud compute service-attachments list --project="$PROJECT"

echo ""
echo -e "${CYAN}━━━ LOAD BALANCING ━━━${NC}"
gsafe "Forwarding Rules" "$OUTPUT_DIR/lb_forwarding_rules.json" gcloud compute forwarding-rules list --project="$PROJECT"
gsafe "Target Pools" "$OUTPUT_DIR/lb_target_pools.json" gcloud compute target-pools list --project="$PROJECT"
gsafe "Backend Services" "$OUTPUT_DIR/lb_backend_services.json" gcloud compute backend-services list --project="$PROJECT"
gsafe "URL Maps" "$OUTPUT_DIR/lb_url_maps.json" gcloud compute url-maps list --project="$PROJECT"
gsafe "Target HTTP Proxies" "$OUTPUT_DIR/lb_target_http_proxies.json" gcloud compute target-http-proxies list --project="$PROJECT"
gsafe "Target HTTPS Proxies" "$OUTPUT_DIR/lb_target_https_proxies.json" gcloud compute target-https-proxies list --project="$PROJECT"
gsafe "SSL Certificates" "$OUTPUT_DIR/lb_ssl_certificates.json" gcloud compute ssl-certificates list --project="$PROJECT"
gsafe "Health Checks" "$OUTPUT_DIR/lb_health_checks.json" gcloud compute health-checks list --project="$PROJECT"
gsafe "NEGs" "$OUTPUT_DIR/lb_negs.json" gcloud compute network-endpoint-groups list --project="$PROJECT"

echo ""
echo -e "${CYAN}━━━ BASES DE DATOS ━━━${NC}"
gsafe "Cloud SQL Instances" "$OUTPUT_DIR/sql_instances.json" gcloud sql instances list --project="$PROJECT"

log "Cloud SQL detalle..."
SQL_DET="$OUTPUT_DIR/sql_instances_detail.json"
echo "[" > "$SQL_DET"
first=true
while IFS= read -r iname; do
    [[ -z "$iname" ]] && continue
    d=$(gcloud sql instances describe "$iname" --project="$PROJECT" --format=json 2>/dev/null)
    if [[ -n "$d" ]]; then $first || echo "," >> "$SQL_DET"; echo "$d" >> "$SQL_DET"; first=false; fi
done < <(gcloud sql instances list --project="$PROJECT" --format="value(name)" 2>/dev/null)
echo "]" >> "$SQL_DET"
ok "Cloud SQL Detail"

# SQL Backups por instancia (fix v2.1)
log "Cloud SQL Backups por instancia..."
SQL_BK="$OUTPUT_DIR/sql_backups.json"
echo "[" > "$SQL_BK"
first=true
while IFS= read -r iname; do
    [[ -z "$iname" ]] && continue
    bk=$(gcloud sql backups list --instance="$iname" --project="$PROJECT" --format=json 2>/dev/null)
    if [[ -n "$bk" && "$bk" != "[]" ]]; then
        $first || echo "," >> "$SQL_BK"
        echo "{\"instance\":\"$iname\",\"backups\":$bk}" >> "$SQL_BK"
        first=false
    fi
done < <(gcloud sql instances list --project="$PROJECT" --format="value(name)" 2>/dev/null)
echo "]" >> "$SQL_BK"
ok "Cloud SQL Backups"

gsafe "Spanner" "$OUTPUT_DIR/spanner_instances.json" gcloud spanner instances list --project="$PROJECT"
gsafe "Firestore DBs" "$OUTPUT_DIR/firestore_databases.json" gcloud firestore databases list --project="$PROJECT"
gsafe "Firestore Indexes" "$OUTPUT_DIR/firestore_indexes.json" gcloud firestore indexes composite list --project="$PROJECT"
gsafe "Bigtable" "$OUTPUT_DIR/bigtable_instances.json" gcloud bigtable instances list --project="$PROJECT"
gsafe "Memorystore Redis" "$OUTPUT_DIR/memorystore_redis.json" gcloud redis instances list --project="$PROJECT" --region="-"
gsafe "Memorystore Memcached" "$OUTPUT_DIR/memorystore_memcached.json" gcloud memcache instances list --project="$PROJECT" --region="-"

echo ""
echo -e "${CYAN}━━━ BIGQUERY ━━━${NC}"
if command -v bq &>/dev/null; then
    csafe "BigQuery Datasets" "$OUTPUT_DIR/bigquery_datasets.json" bq ls --project_id="$PROJECT" --format=json
    BQ_T="$OUTPUT_DIR/bigquery_tables.json"
    echo "[" > "$BQ_T"
    first=true
    while IFS= read -r ds; do
        [[ -z "$ds" ]] && continue
        ds_clean=$(echo "$ds" | tr -d ' ')
        tables=$(bq ls --project_id="$PROJECT" --format=json "${PROJECT}:${ds_clean}" 2>/dev/null)
        if [[ -n "$tables" && "$tables" != "[]" ]]; then
            $first || echo "," >> "$BQ_T"
            echo "{\"dataset\":\"$ds_clean\",\"tables\":$tables}" >> "$BQ_T"
            first=false
        fi
    done < <(bq ls --project_id="$PROJECT" --format=csv 2>/dev/null | tail -n +2 | awk -F',' '{print $1}')
    echo "]" >> "$BQ_T"
    ok "BigQuery Tables"
else
    echo "[]" > "$OUTPUT_DIR/bigquery_datasets.json"
    warn "BigQuery (bq no disponible)"
fi

echo ""
echo -e "${CYAN}━━━ CLOUD STORAGE ━━━${NC}"
gsafe "GCS Buckets" "$OUTPUT_DIR/gcs_buckets.json" gcloud storage buckets list --project="$PROJECT"
log "Detalle de buckets..."
GCS_D="$OUTPUT_DIR/gcs_buckets_detail.json"
echo "[" > "$GCS_D"
first=true
while IFS= read -r bucket; do
    [[ -z "$bucket" ]] && continue
    d=$(gcloud storage buckets describe "$bucket" --format=json 2>/dev/null)
    if [[ -n "$d" ]]; then $first || echo "," >> "$GCS_D"; echo "$d" >> "$GCS_D"; first=false; fi
done < <(gcloud storage buckets list --project="$PROJECT" --format="value(name)" 2>/dev/null)
echo "]" >> "$GCS_D"
ok "GCS Buckets Detail"

echo ""
echo -e "${CYAN}━━━ PUB/SUB ━━━${NC}"
gsafe "Topics" "$OUTPUT_DIR/pubsub_topics.json" gcloud pubsub topics list --project="$PROJECT"
gsafe "Subscriptions" "$OUTPUT_DIR/pubsub_subscriptions.json" gcloud pubsub subscriptions list --project="$PROJECT"
gsafe "Schemas" "$OUTPUT_DIR/pubsub_schemas.json" gcloud pubsub schemas list --project="$PROJECT"

echo ""
echo -e "${CYAN}━━━ TASKS / SCHEDULER ━━━${NC}"
gsafe "Cloud Tasks" "$OUTPUT_DIR/tasks_queues.json" gcloud tasks queues list --project="$PROJECT"
gsafe "Cloud Scheduler" "$OUTPUT_DIR/scheduler_jobs.json" gcloud scheduler jobs list --project="$PROJECT" --location="-"

echo ""
echo -e "${CYAN}━━━ DNS ━━━${NC}"
gsafe "DNS Zones" "$OUTPUT_DIR/dns_zones.json" gcloud dns managed-zones list --project="$PROJECT"
log "DNS records..."
DNS_R="$OUTPUT_DIR/dns_records.json"
echo "[" > "$DNS_R"
first=true
while IFS= read -r zn; do
    [[ -z "$zn" ]] && continue
    recs=$(gcloud dns record-sets list --zone="$zn" --project="$PROJECT" --format=json 2>/dev/null)
    if [[ -n "$recs" && "$recs" != "[]" ]]; then
        $first || echo "," >> "$DNS_R"
        echo "{\"zone\":\"$zn\",\"records\":$recs}" >> "$DNS_R"
        first=false
    fi
done < <(gcloud dns managed-zones list --project="$PROJECT" --format="value(name)" 2>/dev/null)
echo "]" >> "$DNS_R"
ok "DNS Records"

echo ""
echo -e "${CYAN}━━━ SEGURIDAD ━━━${NC}"
gsafe "Cloud Armor" "$OUTPUT_DIR/armor_policies.json" gcloud compute security-policies list --project="$PROJECT"
gsafe "Secrets (metadata)" "$OUTPUT_DIR/secrets.json" gcloud secrets list --project="$PROJECT"

# KMS dinámico (fix v2.1)
log "KMS (ubicaciones dinámicas)..."
KMS_LOCS=$(gcloud kms locations list --project="$PROJECT" --format="value(locationId)" 2>/dev/null)
KMS_FILE="$OUTPUT_DIR/kms_keys.json"
echo "[" > "$KMS_FILE"
first=true
for loc in $KMS_LOCS; do
    while IFS= read -r kr; do
        [[ -z "$kr" ]] && continue
        keys=$(gcloud kms keys list --keyring="$kr" --location="$loc" --project="$PROJECT" --format=json 2>/dev/null)
        $first || echo "," >> "$KMS_FILE"
        echo "{\"location\":\"$loc\",\"keyring\":\"$kr\",\"keys\":${keys:-[]}}" >> "$KMS_FILE"
        first=false
    done < <(gcloud kms keyrings list --location="$loc" --project="$PROJECT" --format="value(name.basename())" 2>/dev/null)
done
echo "]" >> "$KMS_FILE"
ok "KMS Keys"

gsafe "Binary Auth" "$OUTPUT_DIR/binauth_policy.json" gcloud container binauthz policy export --project="$PROJECT"

echo ""
echo -e "${CYAN}━━━ CI/CD ━━━${NC}"
gsafe "Build Triggers" "$OUTPUT_DIR/build_triggers.json" gcloud builds triggers list --project="$PROJECT" --region=global
gsafe "Build Recent" "$OUTPUT_DIR/build_recent.json" gcloud builds list --project="$PROJECT" --limit=20
gsafe "Artifact Registry" "$OUTPUT_DIR/artifact_registry.json" gcloud artifacts repositories list --project="$PROJECT"
gsafe "Container Registry" "$OUTPUT_DIR/container_registry.json" gcloud container images list --project="$PROJECT"
gsafe "Cloud Deploy" "$OUTPUT_DIR/deploy_pipelines.json" gcloud deploy delivery-pipelines list --project="$PROJECT" --region="-"

echo ""
echo -e "${CYAN}━━━ DATA / ANALYTICS ━━━${NC}"
gsafe "Dataflow Jobs" "$OUTPUT_DIR/dataflow_jobs.json" gcloud dataflow jobs list --project="$PROJECT" --region="-" --status=all
gsafe "Dataproc" "$OUTPUT_DIR/dataproc_clusters.json" gcloud dataproc clusters list --project="$PROJECT" --region="-"
gsafe "Composer" "$OUTPUT_DIR/composer_envs.json" gcloud composer environments list --project="$PROJECT" --locations="-"
gsafe "Data Fusion" "$OUTPUT_DIR/datafusion_instances.json" gcloud data-fusion instances list --project="$PROJECT" --location="-"

echo ""
echo -e "${CYAN}━━━ VERTEX AI (multi-región, fix v2.1) ━━━${NC}"
VERTEX_REGIONS=("us-central1" "us-east1" "us-west1" "southamerica-east1" "europe-west1" "europe-west4" "asia-east1" "asia-southeast1")
VX_FILE="$OUTPUT_DIR/vertex_ai.json"
echo "[" > "$VX_FILE"
first=true
for region in "${VERTEX_REGIONS[@]}"; do
    ds=$(gcloud ai datasets list --project="$PROJECT" --region="$region" --format=json 2>/dev/null)
    mo=$(gcloud ai models list --project="$PROJECT" --region="$region" --format=json 2>/dev/null)
    ep=$(gcloud ai endpoints list --project="$PROJECT" --region="$region" --format=json 2>/dev/null)
    if [[ ("$ds" != "[]" && -n "$ds") || ("$mo" != "[]" && -n "$mo") || ("$ep" != "[]" && -n "$ep") ]]; then
        $first || echo "," >> "$VX_FILE"
        echo "{\"region\":\"$region\",\"datasets\":${ds:-[]},\"models\":${mo:-[]},\"endpoints\":${ep:-[]}}" >> "$VX_FILE"
        first=false
    fi
done
echo "]" >> "$VX_FILE"
ok "Vertex AI (${#VERTEX_REGIONS[@]} regiones)"

echo ""
echo -e "${CYAN}━━━ EVENTOS ━━━${NC}"
gsafe "Eventarc" "$OUTPUT_DIR/eventarc_triggers.json" gcloud eventarc triggers list --project="$PROJECT" --location="-"

echo ""
echo -e "${CYAN}━━━ MONITOREO ━━━${NC}"
gsafe "Alert Policies" "$OUTPUT_DIR/monitoring_alerts.json" gcloud alpha monitoring policies list --project="$PROJECT"
gsafe "Uptime Checks" "$OUTPUT_DIR/monitoring_uptime.json" gcloud monitoring uptime list-configs --project="$PROJECT"
gsafe "Log Sinks" "$OUTPUT_DIR/logging_sinks.json" gcloud logging sinks list --project="$PROJECT"
gsafe "Log Buckets" "$OUTPUT_DIR/logging_buckets.json" gcloud logging buckets list --project="$PROJECT" --location="-"
gsafe "Log Metrics" "$OUTPUT_DIR/logging_metrics.json" gcloud logging metrics list --project="$PROJECT"

echo ""
echo -e "${CYAN}━━━ SERVICIOS ADICIONALES ━━━${NC}"
gsafe "IAP Brands" "$OUTPUT_DIR/iap_brands.json" gcloud iap oauth-brands list --project="$PROJECT"
gsafe "Org Policies" "$OUTPUT_DIR/org_policies.json" gcloud org-policies list --project="$PROJECT"
gsafe "APIs Habilitadas" "$OUTPUT_DIR/services_enabled.json" gcloud services list --project="$PROJECT" --enabled
gsafe "Billing Info" "$OUTPUT_DIR/billing_info.json" gcloud billing projects describe "$PROJECT"

# =============================================================================
# _status.json + FALSOS NEGATIVOS
# =============================================================================

echo ""
echo -e "${CYAN}━━━ MANIFIESTO DE ESTADO ━━━${NC}"
STATUS_FILE="$OUTPUT_DIR/_status.json"
{
    echo "["
    first=true
    for key in "${!SERVICE_STATUS[@]}"; do
        $first || echo ","
        printf '{"service":"%s","status":"%s","count":%s,"message":"%s"}' \
            "$key" "${SERVICE_STATUS[$key]}" "${SERVICE_COUNT[$key]:-0}" \
            "$(echo "${SERVICE_MSG[$key]:-}" | tr '"' "'" | head -c 200)"
        first=false
    done
    echo "]"
} > "$STATUS_FILE"
ok "Manifiesto: _status.json"

FALSE_NEG=0
for key in "${!SERVICE_STATUS[@]}"; do
    s="${SERVICE_STATUS[$key]}"
    if [[ "$s" == "sin_permiso" || "$s" == "api_deshabilitada" ]]; then
        ((FALSE_NEG++)) || true
        echo -e "  ${YELLOW}⚠${NC} $key → $s"
    fi
done
[[ $FALSE_NEG -eq 0 ]] && echo -e "  ${GREEN}Ningún falso negativo detectado.${NC}"

# =============================================================================
# ENSAMBLAJE JSON MAESTRO
# =============================================================================

echo ""
echo -e "${CYAN}━━━ ENSAMBLANDO JSON MAESTRO ━━━${NC}"
MASTER="$OUTPUT_DIR/levantamiento_completo.json"

python3 -c "
import json, os, sys
d = sys.argv[1]
m = {'_metadata':{}, '_status':[], 'services':{}}
for f in sorted(os.listdir(d)):
    if not f.endswith('.json') or f=='levantamiento_completo.json': continue
    try:
        data = json.load(open(os.path.join(d,f)))
        k = f.replace('.json','')
        if k=='_metadata': m['_metadata']=data
        elif k=='_status': m['_status']=data
        else: m['services'][k]=data
    except: pass
json.dump(m, open(os.path.join(d,'levantamiento_completo.json'),'w'), indent=2, default=str)
print(f'Servicios: {len(m[\"services\"])}')
" "$OUTPUT_DIR" 2>/dev/null && ok "JSON maestro generado" || {
    log "Fallback jq..."
    echo "{}" > "$MASTER"
    for f in "$OUTPUT_DIR"/*.json; do
        [[ "$(basename "$f")" == "levantamiento_completo.json" ]] && continue
        k=$(basename "$f" .json)
        jq --arg k "$k" --slurpfile v "$f" '.[$k] = $v[0]' "$MASTER" > "${MASTER}.tmp" && mv "${MASTER}.tmp" "$MASTER"
    done
    ok "JSON maestro (jq)"
}

# =============================================================================
# RESUMEN
# =============================================================================

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
TOTAL_SIZE=$(du -sh "$OUTPUT_DIR" 2>/dev/null | awk '{print $1}')
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.json" | wc -l)

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    RESUMEN FINAL                              ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Proyecto:         ${GREEN}$PROJECT${NC}"
echo -e "  Servicios OK:     ${GREEN}$OK${NC}"
echo -e "  Warnings:         ${YELLOW}$ERRORS${NC}"
echo -e "  Falsos negativos: ${YELLOW}$FALSE_NEG${NC}"
echo -e "  Archivos JSON:    $FILE_COUNT"
echo -e "  Tamaño total:     $TOTAL_SIZE"	
echo -e "  Duración:         ${DURATION}s"
echo -e "  Output:           ${GREEN}$OUTPUT_DIR/${NC}"
echo ""
echo -e "  ${GREEN}✓ Levantamiento completado${NC}"
echo ""
echo -e "  Comprimir y descargar:"
echo -e "    ${YELLOW}tar czf levantamiento_gcp.tar.gz $OUTPUT_DIR/${NC}"
echo -e "    ${YELLOW}cloudshell download levantamiento_gcp.tar.gz${NC}"
echo ""
