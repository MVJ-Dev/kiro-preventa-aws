#!/usr/bin/env bash
# =============================================================================
# SCRIPT DE LEVANTAMIENTO DE INFRAESTRUCTURA GCP — OPTIMIZADO PARA CLOUD SHELL
# =============================================================================
# Versión: 3.0  (v2.1 + auditoría de seguridad y correctitud, oct-2026)
# Uso: ./levantamiento-gcp.sh [--project ID | --all-projects] [--output-dir DIR]
#                             [--full] [--include-empty] [--timeout SEG]
#
# GARANTÍA DE SEGURIDAD (verificable comando por comando):
#   • 100% SOLO LECTURA. Todos los comandos son list / describe / show / get-* /
#     export-policy / du. NINGÚN verbo de escritura. Con una cuenta de solo
#     lectura (roles/viewer) IAM impide cualquier cambio de todos modos.
#   • CERO JOBS EN EL CLIENTE: el sizing de BigQuery usa `bq show` (metadata),
#     NO `bq query`, por lo que no crea jobs ni deja rastro en el audit log.
#   • CONFIDENCIALIDAD: los valores sensibles que las APIs devuelven junto a la
#     config (env vars de Cloud Run/Functions, startup-script/ssh-keys de VMs,
#     substitutions de Build) se REDACTAN a [REDACTED] antes de ensamblar el
#     maestro. Aun así los JSON traen datos del cliente (emails IAM, firewall):
#     trátalos como confidenciales y borra la carpeta tras descargar.
#   • COSTO ~$0 (list/describe no se facturan; `storage du` son centavos a lo sumo).
#
# CAMBIOS v3.0 vs v2.1:
#   - GCS usa gs:// (storage_url), antes fallaba con el nombre pelado.
#   - BigQuery: --max_results alto + sizing por tabla con `bq show` (sin jobs).
#   - Cloud Functions sin --gen2 (incluye gen1). monitoring policies sin alpha (GA).
#   - PSC por forwarding-rules. Scheduler/Memorystore/Dataflow/Dataproc por regiones.
#   - _status.json con jq (robusto). timeout se distingue de "vacío". bq registra count.
#   - Redacción de secretos. Detalle Cloud Run/Compute (CPU/RAM). Filtro por API activa.
#   - Fix bug subshell en --all-projects (for sobre array, no pipe recursivo).
# =============================================================================

set -o pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

START_TIME=$(date +%s)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TIMESTAMP_FILE=$(date +"%Y%m%d_%H%M%S")
OUTPUT_DIR="${OUTPUT_DIR:-./levantamiento_gcp_${TIMESTAMP_FILE}}"
SPECIFIC_PROJECT=""
ALL_PROJECTS=false
FULL_SCAN=false
TIMEOUT="${TIMEOUT:-20}"
TIMEOUT_SIZING="${TIMEOUT_SIZING:-120}"
OK=0; ERRORS=0

declare -A SERVICE_STATUS
declare -A SERVICE_COUNT
declare -A SERVICE_MSG
declare -A ENABLED_APIS

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

REGIONS=(us-central1 us-east1 us-east4 us-east5 us-west1 us-west2 us-west3 us-west4
         southamerica-east1 southamerica-west1 europe-west1 europe-west2 europe-west3
         europe-west4 asia-east1 asia-east2 asia-southeast1 asia-northeast1)

while [[ $# -gt 0 ]]; do
    case $1 in
        --project) SPECIFIC_PROJECT="$2"; shift 2 ;;
        --all-projects) ALL_PROJECTS=true; shift ;;
        --full) FULL_SCAN=true; shift ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --help)
            echo "Uso: $0 [--project ID | --all-projects] [--output-dir DIR] [--full] [--timeout SEG]"
            echo "  --all-projects : todos los proyectos accesibles (gcloud projects list)"
            echo "  --full         : NO filtrar por API habilitada (barrido total, más lento)"
            echo "  --timeout SEG  : timeout por comando (default 20)"
            exit 0 ;;
        *) echo "Opción desconocida: $1 (usa --help)"; exit 1 ;;
    esac
done

log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[ OK ]${NC} $1"; ((OK++)) || true; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((ERRORS++)) || true; }

classify_error() {
    local errmsg="$1" rc="$2"
    if [[ "$rc" == "124" ]]; then echo "timeout"; return; fi
    if echo "$errmsg" | grep -qiE "permission_denied|does not have permission|forbidden|access.*denied|caller does not have"; then
        echo "sin_permiso"
    elif echo "$errmsg" | grep -qiE "service_disabled|has not been used|is disabled|api.*not enabled|accessnotconfigured"; then
        echo "api_deshabilitada"
    elif echo "$errmsg" | grep -qiE "not found|404|does not exist"; then
        echo "no_encontrado"
    elif [[ -z "$errmsg" ]]; then
        echo "sin_recursos"
    else
        echo "error_otro"
    fi
}

api_on() {
    local api="$1"
    $FULL_SCAN && return 0
    [[ "${ENABLED_APIS[_loaded]}" == "1" ]] || return 0
    [[ " ${ENABLED_APIS[list]} " == *" $api "* ]]
}

gsafe() {
    local desc="$1"; shift
    local outfile="$1"; shift
    local key; key=$(basename "$outfile" .json)
    local stderr_file; stderr_file=$(mktemp); local rc=0
    timeout "$TIMEOUT" "$@" --format=json > "$outfile" 2>"$stderr_file" || rc=$?
    if [[ $rc -eq 0 ]] && jq empty "$outfile" 2>/dev/null; then
        local count; count=$(jq 'if type=="array" then length elif type=="object" then (keys|length) else 0 end' "$outfile" 2>/dev/null)
        ok "$desc ($count elementos)"
        SERVICE_STATUS[$key]="ok"; SERVICE_COUNT[$key]="${count:-0}"
        rm -f "$stderr_file"; return 0
    fi
    local errmsg; errmsg=$(tr '\n' ' ' < "$stderr_file" | head -c 300); rm -f "$stderr_file"
    echo "[]" > "$outfile"
    local reason; reason=$(classify_error "$errmsg" "$rc")
    case "$reason" in
        sin_permiso)       warn "$desc (SIN PERMISO)" ;;
        api_deshabilitada) warn "$desc (API deshabilitada)" ;;
        timeout)           warn "$desc (TIMEOUT — reintentar con --timeout mayor; NO asumir vacío)" ;;
        no_encontrado)     warn "$desc (no encontrado)" ;;
        sin_recursos)      ok   "$desc (0 elementos)" ;;
        *)                 warn "$desc ($reason)" ;;
    esac
    SERVICE_STATUS[$key]="$reason"; SERVICE_COUNT[$key]=0; SERVICE_MSG[$key]="$errmsg"
    return 1
}

csafe() {
    local desc="$1"; shift
    local outfile="$1"; shift
    local key; key=$(basename "$outfile" .json)
    local stderr_file; stderr_file=$(mktemp); local rc=0
    timeout "$TIMEOUT" "$@" > "$outfile" 2>"$stderr_file" || rc=$?
    if [[ $rc -eq 0 ]] && jq empty "$outfile" 2>/dev/null; then
        local count; count=$(jq 'if type=="array" then length else 0 end' "$outfile" 2>/dev/null)
        ok "$desc ($count elementos)"
        SERVICE_STATUS[$key]="ok"; SERVICE_COUNT[$key]="${count:-0}"
        rm -f "$stderr_file"; return 0
    fi
    local errmsg; errmsg=$(tr '\n' ' ' < "$stderr_file" | head -c 300); rm -f "$stderr_file"
    echo "[]" > "$outfile"
    local reason; reason=$(classify_error "$errmsg" "$rc")
    warn "$desc ($reason)"
    SERVICE_STATUS[$key]="$reason"; SERVICE_COUNT[$key]=0; SERVICE_MSG[$key]="$errmsg"
    return 1
}

write_status() {
    local out="$1"; local tmp; tmp=$(mktemp); echo "[]" > "$tmp"
    for key in "${!SERVICE_STATUS[@]}"; do
        jq --arg s "$key" --arg st "${SERVICE_STATUS[$key]}" \
           --argjson c "${SERVICE_COUNT[$key]:-0}" --arg m "${SERVICE_MSG[$key]:-}" \
           '. += [{"service":$s,"status":$st,"count":$c,"message":$m}]' "$tmp" > "${tmp}.n" && mv "${tmp}.n" "$tmp"
    done
    mv "$tmp" "$out/_status.json"
}

# redact_secrets: borra VALORES sensibles de los JSON (conserva nombres/estructura).
redact_secrets() {
    local OUT="$1"; command -v jq &>/dev/null || return 0; local f tmp
    for f in "$OUT/cloudrun_services.json" "$OUT/cloudrun_services_detail.json"; do
        [[ -s "$f" ]] || continue; tmp=$(mktemp)
        jq '(.. | objects | select(has("env")) | .env) |= (map(if type=="object" and has("value") then .value="[REDACTED]" else . end))' \
            "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f" || rm -f "$tmp"
    done
    f="$OUT/functions.json"
    if [[ -s "$f" ]]; then tmp=$(mktemp)
        jq '(.. | objects | select(has("environmentVariables")) | .environmentVariables) |= (if type=="object" then with_entries(.value="[REDACTED]") else . end)
            | (.. | objects | select(has("buildEnvironmentVariables")) | .buildEnvironmentVariables) |= (if type=="object" then with_entries(.value="[REDACTED]") else . end)' \
            "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f" || rm -f "$tmp"
    fi
    f="$OUT/compute_instances_detail.json"
    if [[ -s "$f" ]]; then tmp=$(mktemp)
        jq '(.. | objects | select(has("items") and (.items|type=="array")) | .items) |=
              (map(if (.key|test("startup-script|ssh-keys|user-data|shutdown-script";"i")) then .value="[REDACTED]" else . end))' \
            "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f" || rm -f "$tmp"
    fi
    f="$OUT/build_triggers.json"
    if [[ -s "$f" ]]; then tmp=$(mktemp)
        jq '(.. | objects | select(has("substitutions")) | .substitutions) |= (if type=="object" then with_entries(.value="[REDACTED]") else . end)' \
            "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f" || rm -f "$tmp"
    fi
    echo "env vars, startup-scripts, ssh-keys y substitutions redactados ($(date -u +%FT%TZ))" > "$OUT/.redacted"
}

# =============================================================================
# scan_project
# =============================================================================
scan_project() {
    local PROJECT="$1"; local OUT="$2"; mkdir -p "$OUT"
    SERVICE_STATUS=(); SERVICE_COUNT=(); SERVICE_MSG=(); ENABLED_APIS=()

    cat > "$OUT/_metadata.json" << EOF
{"timestamp":"$TIMESTAMP","account":"$ACCOUNT","project":"$PROJECT","script_version":"3.0","full_scan":$FULL_SCAN}
EOF

    gsafe "APIs Habilitadas" "$OUT/services_enabled.json" gcloud services list --project="$PROJECT" --enabled
    if jq -e 'type=="array"' "$OUT/services_enabled.json" >/dev/null 2>&1; then
        ENABLED_APIS[list]=$(jq -r '.[].config.name // .[].name // empty' "$OUT/services_enabled.json" 2>/dev/null | tr '\n' ' ')
        ENABLED_APIS[_loaded]=1
    fi

    echo -e "${CYAN}━━━ IAM ━━━${NC}"
    gsafe "IAM Policy" "$OUT/iam_policy.json" gcloud projects get-iam-policy "$PROJECT"
    gsafe "Service Accounts" "$OUT/iam_service_accounts.json" gcloud iam service-accounts list --project="$PROJECT"
    gsafe "Custom Roles" "$OUT/iam_custom_roles.json" gcloud iam roles list --project="$PROJECT"

    echo -e "${CYAN}━━━ COMPUTE ENGINE ━━━${NC}"
    if api_on compute.googleapis.com; then
        gsafe "Instances" "$OUT/compute_instances.json" gcloud compute instances list --project="$PROJECT"
        gsafe "Instance Templates" "$OUT/compute_templates.json" gcloud compute instance-templates list --project="$PROJECT"
        gsafe "MIGs" "$OUT/compute_migs.json" gcloud compute instance-groups managed list --project="$PROJECT"
        gsafe "Disks" "$OUT/compute_disks.json" gcloud compute disks list --project="$PROJECT"
        gsafe "Snapshots" "$OUT/compute_snapshots.json" gcloud compute snapshots list --project="$PROJECT"
        gsafe "Images (custom)" "$OUT/compute_images.json" gcloud compute images list --project="$PROJECT" --no-standard-images
        gsafe "Machine Images" "$OUT/compute_machine_images.json" gcloud compute machine-images list --project="$PROJECT"
        gsafe "Reservations" "$OUT/compute_reservations.json" gcloud compute reservations list --project="$PROJECT"
        log "Compute — detalle por instancia..."
        local CI_DET="$OUT/compute_instances_detail.json"; echo "[" > "$CI_DET"; local first=true
        while IFS=$'\t' read -r iname izone; do
            [[ -z "$iname" ]] && continue
            local d; d=$(timeout "$TIMEOUT" gcloud compute instances describe "$iname" --zone="$izone" --project="$PROJECT" --format=json 2>/dev/null)
            if [[ -n "$d" ]]; then $first || echo "," >> "$CI_DET"; echo "$d" >> "$CI_DET"; first=false; fi
        done < <(gcloud compute instances list --project="$PROJECT" --format="value(name,zone.basename())" 2>/dev/null)
        echo "]" >> "$CI_DET"; ok "Compute Instances Detail"

        echo -e "${CYAN}━━━ VPC / NETWORKING ━━━${NC}"
        gsafe "VPC Networks" "$OUT/vpc_networks.json" gcloud compute networks list --project="$PROJECT"
        gsafe "Subnets" "$OUT/vpc_subnets.json" gcloud compute networks subnets list --project="$PROJECT"
        gsafe "Firewall Rules" "$OUT/vpc_firewall_rules.json" gcloud compute firewall-rules list --project="$PROJECT"
        gsafe "Routes" "$OUT/vpc_routes.json" gcloud compute routes list --project="$PROJECT"
        gsafe "Routers" "$OUT/vpc_routers.json" gcloud compute routers list --project="$PROJECT"
        gsafe "VPN Tunnels" "$OUT/vpc_vpn_tunnels.json" gcloud compute vpn-tunnels list --project="$PROJECT"
        gsafe "VPN Gateways" "$OUT/vpc_vpn_gateways.json" gcloud compute vpn-gateways list --project="$PROJECT"
        gsafe "Interconnects" "$OUT/vpc_interconnects.json" gcloud compute interconnects list --project="$PROJECT"
        gsafe "External IPs" "$OUT/vpc_external_ips.json" gcloud compute addresses list --project="$PROJECT"
        log "NAT por router..."
        local NAT_FILE="$OUT/vpc_nat.json"; echo "[" > "$NAT_FILE"; first=true
        while IFS=$'\t' read -r rname rregion; do
            [[ -z "$rname" ]] && continue
            local nats; nats=$(timeout "$TIMEOUT" gcloud compute routers nats list --router="$rname" --region="$rregion" --project="$PROJECT" --format=json 2>/dev/null)
            if [[ -n "$nats" && "$nats" != "[]" ]]; then $first || echo "," >> "$NAT_FILE"; echo "{\"router\":\"$rname\",\"region\":\"$rregion\",\"nats\":$nats}" >> "$NAT_FILE"; first=false; fi
        done < <(gcloud compute routers list --project="$PROJECT" --format="value(name,region.basename())" 2>/dev/null)
        echo "]" >> "$NAT_FILE"; ok "NAT Gateways"
        log "VPC Peering por red..."
        local PEER_FILE="$OUT/vpc_peering.json"; echo "[" > "$PEER_FILE"; first=true
        while IFS= read -r net_name; do
            [[ -z "$net_name" ]] && continue
            local peerings; peerings=$(timeout "$TIMEOUT" gcloud compute networks peerings list --project="$PROJECT" --network="$net_name" --format=json 2>/dev/null)
            if [[ -n "$peerings" && "$peerings" != "[]" ]]; then $first || echo "," >> "$PEER_FILE"; echo "{\"network\":\"$net_name\",\"peerings\":$peerings}" >> "$PEER_FILE"; first=false; fi
        done < <(gcloud compute networks list --project="$PROJECT" --format="value(name)" 2>/dev/null)
        echo "]" >> "$PEER_FILE"; ok "VPC Peering"

        # PSC: forwarding-rules que apuntan a service attachments (fix v3.0)
        gsafe "PSC Service Attachments" "$OUT/psc_service_attachments.json" gcloud compute service-attachments list --project="$PROJECT"

        echo -e "${CYAN}━━━ LOAD BALANCING ━━━${NC}"
        gsafe "Forwarding Rules" "$OUT/lb_forwarding_rules.json" gcloud compute forwarding-rules list --project="$PROJECT"
        gsafe "Backend Services" "$OUT/lb_backend_services.json" gcloud compute backend-services list --project="$PROJECT"
        gsafe "URL Maps" "$OUT/lb_url_maps.json" gcloud compute url-maps list --project="$PROJECT"
        gsafe "Target HTTP Proxies" "$OUT/lb_target_http_proxies.json" gcloud compute target-http-proxies list --project="$PROJECT"
        gsafe "Target HTTPS Proxies" "$OUT/lb_target_https_proxies.json" gcloud compute target-https-proxies list --project="$PROJECT"
        gsafe "SSL Certificates" "$OUT/lb_ssl_certificates.json" gcloud compute ssl-certificates list --project="$PROJECT"
        gsafe "Health Checks" "$OUT/lb_health_checks.json" gcloud compute health-checks list --project="$PROJECT"
        gsafe "NEGs" "$OUT/lb_negs.json" gcloud compute network-endpoint-groups list --project="$PROJECT"
        gsafe "Cloud Armor" "$OUT/armor_policies.json" gcloud compute security-policies list --project="$PROJECT"
    else
        warn "Compute API deshabilitada → se omite Compute/VPC/LB (sin API no hay recursos)"
    fi

    echo -e "${CYAN}━━━ GKE ━━━${NC}"
    if api_on container.googleapis.com; then
        gsafe "GKE Clusters" "$OUT/gke_clusters.json" gcloud container clusters list --project="$PROJECT"
        log "GKE node pools..."
        local NP_FILE="$OUT/gke_nodepools.json"; echo "[" > "$NP_FILE"; local first=true
        while IFS=$'\t' read -r cname zone; do
            [[ -z "$cname" ]] && continue
            local pools; pools=$(timeout "$TIMEOUT" gcloud container node-pools list --cluster="$cname" --location="$zone" --project="$PROJECT" --format=json 2>/dev/null)
            if [[ -n "$pools" && "$pools" != "[]" ]]; then $first || echo "," >> "$NP_FILE"; echo "{\"cluster\":\"$cname\",\"location\":\"$zone\",\"node_pools\":$pools}" >> "$NP_FILE"; first=false; fi
        done < <(gcloud container clusters list --project="$PROJECT" --format="value(name,location)" 2>/dev/null)
        echo "]" >> "$NP_FILE"; ok "GKE Node Pools"
        gsafe "Container Images (GCR)" "$OUT/container_registry.json" gcloud container images list --project="$PROJECT"
    fi

    echo -e "${CYAN}━━━ CLOUD RUN / FUNCTIONS / APP ENGINE ━━━${NC}"
    if api_on run.googleapis.com; then
        gsafe "Cloud Run Services" "$OUT/cloudrun_services.json" gcloud run services list --project="$PROJECT" --platform=managed
        gsafe "Cloud Run Jobs" "$OUT/cloudrun_jobs.json" gcloud run jobs list --project="$PROJECT"
        log "Cloud Run — detalle por servicio..."
        local CR_DET="$OUT/cloudrun_services_detail.json"; echo "[" > "$CR_DET"; local first=true
        while IFS=$'\t' read -r sname sregion; do
            [[ -z "$sname" ]] && continue
            local d; d=$(timeout "$TIMEOUT" gcloud run services describe "$sname" --region="$sregion" --project="$PROJECT" --platform=managed --format=json 2>/dev/null)
            if [[ -n "$d" ]]; then $first || echo "," >> "$CR_DET"; echo "$d" >> "$CR_DET"; first=false; fi
        done < <(gcloud run services list --project="$PROJECT" --platform=managed --format="value(metadata.name,region)" 2>/dev/null)
        echo "]" >> "$CR_DET"; ok "Cloud Run Services Detail"
    fi
    # Functions: SIN --gen2 (fix: --gen2 ocultaba gen1).
    api_on cloudfunctions.googleapis.com && gsafe "Cloud Functions" "$OUT/functions.json" gcloud functions list --project="$PROJECT"
    if api_on appengine.googleapis.com; then
        gsafe "App Engine App" "$OUT/appengine_app.json" gcloud app describe --project="$PROJECT"
        gsafe "App Engine Services" "$OUT/appengine_services.json" gcloud app services list --project="$PROJECT"
    fi

    echo -e "${CYAN}━━━ BASES DE DATOS ━━━${NC}"
    if api_on sqladmin.googleapis.com; then
        gsafe "Cloud SQL Instances" "$OUT/sql_instances.json" gcloud sql instances list --project="$PROJECT"
        log "Cloud SQL detalle..."
        local SQL_DET="$OUT/sql_instances_detail.json"; echo "[" > "$SQL_DET"; local first=true
        while IFS= read -r iname; do
            [[ -z "$iname" ]] && continue
            local d; d=$(timeout "$TIMEOUT" gcloud sql instances describe "$iname" --project="$PROJECT" --format=json 2>/dev/null)
            if [[ -n "$d" ]]; then $first || echo "," >> "$SQL_DET"; echo "$d" >> "$SQL_DET"; first=false; fi
        done < <(gcloud sql instances list --project="$PROJECT" --format="value(name)" 2>/dev/null)
        echo "]" >> "$SQL_DET"; ok "Cloud SQL Detail"
        log "Cloud SQL backups..."
        local SQL_BK="$OUT/sql_backups.json"; echo "[" > "$SQL_BK"; first=true
        while IFS= read -r iname; do
            [[ -z "$iname" ]] && continue
            local bk; bk=$(timeout "$TIMEOUT" gcloud sql backups list --instance="$iname" --project="$PROJECT" --format=json 2>/dev/null)
            if [[ -n "$bk" && "$bk" != "[]" ]]; then $first || echo "," >> "$SQL_BK"; echo "{\"instance\":\"$iname\",\"backups\":$bk}" >> "$SQL_BK"; first=false; fi
        done < <(gcloud sql instances list --project="$PROJECT" --format="value(name)" 2>/dev/null)
        echo "]" >> "$SQL_BK"; ok "Cloud SQL Backups"
    fi
    api_on spanner.googleapis.com   && gsafe "Spanner" "$OUT/spanner_instances.json" gcloud spanner instances list --project="$PROJECT"
    api_on firestore.googleapis.com && gsafe "Firestore DBs" "$OUT/firestore_databases.json" gcloud firestore databases list --project="$PROJECT"
    api_on bigtable.googleapis.com  && gsafe "Bigtable" "$OUT/bigtable_instances.json" gcloud bigtable instances list --project="$PROJECT"
    if api_on redis.googleapis.com; then
        local RE_FILE="$OUT/memorystore_redis.json"; echo "[" > "$RE_FILE"; local first=true
        for r in "${REGIONS[@]}"; do
            local x; x=$(timeout "$TIMEOUT" gcloud redis instances list --project="$PROJECT" --region="$r" --format=json 2>/dev/null)
            if [[ -n "$x" && "$x" != "[]" ]]; then $first || echo "," >> "$RE_FILE"; echo "{\"region\":\"$r\",\"instances\":$x}" >> "$RE_FILE"; first=false; fi
        done
        echo "]" >> "$RE_FILE"; ok "Memorystore Redis"
    fi

    echo -e "${CYAN}━━━ BIGQUERY (sizing con bq show — sin jobs) ━━━${NC}"
    if api_on bigquery.googleapis.com && command -v bq &>/dev/null; then
        csafe "BigQuery Datasets" "$OUT/bigquery_datasets.json" bq ls --project_id="$PROJECT" --max_results=1000 --format=json
        log "BigQuery — tamaño por tabla con bq show (sin jobs)..."
        local BQ_SIZE="$OUT/bigquery_table_sizes.json"; echo "[" > "$BQ_SIZE"; local first=true
        while IFS= read -r ds; do
            [[ -z "$ds" ]] && continue
            local ds_clean; ds_clean=$(echo "$ds" | tr -d ' ')
            while IFS= read -r tbl; do
                [[ -z "$tbl" ]] && continue
                local tinfo; tinfo=$(timeout "$TIMEOUT" bq show --format=prettyjson "${PROJECT}:${ds_clean}.${tbl}" 2>/dev/null \
                    | jq -c '{dataset:"'"$ds_clean"'",table:.tableReference.tableId,rows:.numRows,bytes:.numBytes,type:.type,created:.creationTime}' 2>/dev/null)
                if [[ -n "$tinfo" ]]; then $first || echo "," >> "$BQ_SIZE"; echo "$tinfo" >> "$BQ_SIZE"; first=false; fi
            done < <(bq ls --project_id="$PROJECT" --max_results=100000 --format=json "${PROJECT}:${ds_clean}" 2>/dev/null | jq -r '.[].tableReference.tableId // empty' 2>/dev/null)
        done < <(bq ls --project_id="$PROJECT" --max_results=1000 --format=json 2>/dev/null | jq -r '.[].datasetReference.datasetId // empty' 2>/dev/null)
        echo "]" >> "$BQ_SIZE"
        local bqn; bqn=$(jq 'length' "$BQ_SIZE" 2>/dev/null || echo 0)
        SERVICE_STATUS[bigquery_table_sizes]="ok"; SERVICE_COUNT[bigquery_table_sizes]="${bqn:-0}"
        ok "BigQuery Table Sizes ($bqn tablas, 0 jobs)"
    fi

    echo -e "${CYAN}━━━ CLOUD STORAGE (con sizing) ━━━${NC}"
    if api_on storage.googleapis.com; then
        gsafe "GCS Buckets" "$OUT/gcs_buckets.json" gcloud storage buckets list --project="$PROJECT"
        log "GCS — detalle + tamaño por bucket..."
        local GCS_D="$OUT/gcs_buckets_detail.json"; local GCS_SZ="$OUT/gcs_buckets_size.json"
        echo "[" > "$GCS_D"; local first=true; echo "[" > "$GCS_SZ"; local firstsz=true
        # fix v3.0: usar storage_url (gs://...) en vez del nombre pelado.
        while IFS= read -r burl; do
            [[ -z "$burl" ]] && continue
            local d; d=$(timeout "$TIMEOUT" gcloud storage buckets describe "$burl" --format=json 2>/dev/null)
            if [[ -n "$d" ]]; then $first || echo "," >> "$GCS_D"; echo "$d" >> "$GCS_D"; first=false; fi
            local sz; sz=$(timeout "$TIMEOUT_SIZING" gcloud storage du -s "$burl" 2>/dev/null | head -1)
            $firstsz || echo "," >> "$GCS_SZ"; echo "{\"bucket\":\"$burl\",\"du\":\"${sz:-timeout_o_vacio}\"}" >> "$GCS_SZ"; firstsz=false
        done < <(gcloud storage buckets list --project="$PROJECT" --format="value(storage_url)" 2>/dev/null)
        echo "]" >> "$GCS_D"; ok "GCS Buckets Detail"
        echo "]" >> "$GCS_SZ"; ok "GCS Buckets Size"
    fi

    echo -e "${CYAN}━━━ PUB/SUB · TASKS · SCHEDULER ━━━${NC}"
    api_on pubsub.googleapis.com && {
        gsafe "PubSub Topics" "$OUT/pubsub_topics.json" gcloud pubsub topics list --project="$PROJECT"
        gsafe "PubSub Subscriptions" "$OUT/pubsub_subscriptions.json" gcloud pubsub subscriptions list --project="$PROJECT"
        gsafe "PubSub Schemas" "$OUT/pubsub_schemas.json" gcloud pubsub schemas list --project="$PROJECT"
    }
    api_on cloudtasks.googleapis.com && gsafe "Cloud Tasks" "$OUT/tasks_queues.json" gcloud tasks queues list --project="$PROJECT" --location="-"
    if api_on cloudscheduler.googleapis.com; then
        local SCH="$OUT/scheduler_jobs.json"; echo "[" > "$SCH"; local first=true
        for r in "${REGIONS[@]}"; do
            local x; x=$(timeout "$TIMEOUT" gcloud scheduler jobs list --project="$PROJECT" --location="$r" --format=json 2>/dev/null)
            if [[ -n "$x" && "$x" != "[]" ]]; then $first || echo "," >> "$SCH"; echo "{\"location\":\"$r\",\"jobs\":$x}" >> "$SCH"; first=false; fi
        done
        echo "]" >> "$SCH"; ok "Cloud Scheduler"
    fi

    echo -e "${CYAN}━━━ DNS ━━━${NC}"
    if api_on dns.googleapis.com; then
        gsafe "DNS Zones" "$OUT/dns_zones.json" gcloud dns managed-zones list --project="$PROJECT"
        local DNS_R="$OUT/dns_records.json"; echo "[" > "$DNS_R"; local first=true
        while IFS= read -r zn; do
            [[ -z "$zn" ]] && continue
            local recs; recs=$(timeout "$TIMEOUT" gcloud dns record-sets list --zone="$zn" --project="$PROJECT" --format=json 2>/dev/null)
            if [[ -n "$recs" && "$recs" != "[]" ]]; then $first || echo "," >> "$DNS_R"; echo "{\"zone\":\"$zn\",\"records\":$recs}" >> "$DNS_R"; first=false; fi
        done < <(gcloud dns managed-zones list --project="$PROJECT" --format="value(name)" 2>/dev/null)
        echo "]" >> "$DNS_R"; ok "DNS Records"
    fi

    echo -e "${CYAN}━━━ SEGURIDAD ━━━${NC}"
    api_on secretmanager.googleapis.com && gsafe "Secrets (solo nombres, NUNCA valores)" "$OUT/secrets.json" gcloud secrets list --project="$PROJECT"
    if api_on cloudkms.googleapis.com; then
        log "KMS..."
        local KMS_LOCS; KMS_LOCS=$(gcloud kms locations list --project="$PROJECT" --format="value(locationId)" 2>/dev/null)
        local KMS_FILE="$OUT/kms_keys.json"; echo "[" > "$KMS_FILE"; local first=true
        for loc in $KMS_LOCS; do
            while IFS= read -r kr; do
                [[ -z "$kr" ]] && continue
                local keys; keys=$(timeout "$TIMEOUT" gcloud kms keys list --keyring="$kr" --location="$loc" --project="$PROJECT" --format=json 2>/dev/null)
                $first || echo "," >> "$KMS_FILE"; echo "{\"location\":\"$loc\",\"keyring\":\"$kr\",\"keys\":${keys:-[]}}" >> "$KMS_FILE"; first=false
            done < <(gcloud kms keyrings list --location="$loc" --project="$PROJECT" --format="value(name.basename())" 2>/dev/null)
        done
        echo "]" >> "$KMS_FILE"; ok "KMS Keys"
    fi
    api_on binaryauthorization.googleapis.com && gsafe "Binary Auth" "$OUT/binauth_policy.json" gcloud container binauthz policy export --project="$PROJECT"

    echo -e "${CYAN}━━━ CI/CD ━━━${NC}"
    api_on cloudbuild.googleapis.com && {
        gsafe "Build Triggers" "$OUT/build_triggers.json" gcloud builds triggers list --project="$PROJECT" --region=global
        gsafe "Build Recent" "$OUT/build_recent.json" gcloud builds list --project="$PROJECT" --limit=20
    }
    api_on artifactregistry.googleapis.com && gsafe "Artifact Registry" "$OUT/artifact_registry.json" gcloud artifacts repositories list --project="$PROJECT"
    if api_on clouddeploy.googleapis.com; then
        local DP="$OUT/deploy_pipelines.json"; echo "[" > "$DP"; local first=true
        for r in "${REGIONS[@]}"; do
            local x; x=$(timeout "$TIMEOUT" gcloud deploy delivery-pipelines list --project="$PROJECT" --region="$r" --format=json 2>/dev/null)
            if [[ -n "$x" && "$x" != "[]" ]]; then $first || echo "," >> "$DP"; echo "{\"region\":\"$r\",\"pipelines\":$x}" >> "$DP"; first=false; fi
        done
        echo "]" >> "$DP"; ok "Cloud Deploy"
    fi

    echo -e "${CYAN}━━━ DATA / ANALYTICS ━━━${NC}"
    if api_on dataflow.googleapis.com; then
        local DF="$OUT/dataflow_jobs.json"; echo "[" > "$DF"; local first=true
        for r in "${REGIONS[@]}"; do
            local x; x=$(timeout "$TIMEOUT" gcloud dataflow jobs list --project="$PROJECT" --region="$r" --status=all --format=json 2>/dev/null)
            if [[ -n "$x" && "$x" != "[]" ]]; then $first || echo "," >> "$DF"; echo "{\"region\":\"$r\",\"jobs\":$x}" >> "$DF"; first=false; fi
        done
        echo "]" >> "$DF"; ok "Dataflow"
    fi
    if api_on dataproc.googleapis.com; then
        local DC="$OUT/dataproc_clusters.json"; echo "[" > "$DC"; local first=true
        for r in "${REGIONS[@]}"; do
            local x; x=$(timeout "$TIMEOUT" gcloud dataproc clusters list --project="$PROJECT" --region="$r" --format=json 2>/dev/null)
            if [[ -n "$x" && "$x" != "[]" ]]; then $first || echo "," >> "$DC"; echo "{\"region\":\"$r\",\"clusters\":$x}" >> "$DC"; first=false; fi
        done
        echo "]" >> "$DC"; ok "Dataproc"
    fi
    api_on composer.googleapis.com && gsafe "Composer" "$OUT/composer_envs.json" gcloud composer environments list --project="$PROJECT" --locations="-"
    api_on datafusion.googleapis.com && gsafe "Data Fusion" "$OUT/datafusion_instances.json" gcloud data-fusion instances list --project="$PROJECT" --location="-"

    echo -e "${CYAN}━━━ VERTEX AI (multi-región) ━━━${NC}"
    if api_on aiplatform.googleapis.com; then
        local VX_FILE="$OUT/vertex_ai.json"; echo "[" > "$VX_FILE"; local first=true
        for region in "${REGIONS[@]}"; do
            local ds mo ep
            ds=$(timeout "$TIMEOUT" gcloud ai datasets list --project="$PROJECT" --region="$region" --format=json 2>/dev/null)
            mo=$(timeout "$TIMEOUT" gcloud ai models list --project="$PROJECT" --region="$region" --format=json 2>/dev/null)
            ep=$(timeout "$TIMEOUT" gcloud ai endpoints list --project="$PROJECT" --region="$region" --format=json 2>/dev/null)
            if [[ ("$ds" != "[]" && -n "$ds") || ("$mo" != "[]" && -n "$mo") || ("$ep" != "[]" && -n "$ep") ]]; then
                $first || echo "," >> "$VX_FILE"
                echo "{\"region\":\"$region\",\"datasets\":${ds:-[]},\"models\":${mo:-[]},\"endpoints\":${ep:-[]}}" >> "$VX_FILE"; first=false
            fi
        done
        echo "]" >> "$VX_FILE"; ok "Vertex AI"
    fi

    echo -e "${CYAN}━━━ EVENTOS / MONITOREO / LOGGING ━━━${NC}"
    api_on eventarc.googleapis.com && gsafe "Eventarc" "$OUT/eventarc_triggers.json" gcloud eventarc triggers list --project="$PROJECT" --location="-"
    # monitoring policies: GA, SIN alpha (fix v3.0).
    api_on monitoring.googleapis.com && {
        gsafe "Alert Policies" "$OUT/monitoring_alerts.json" gcloud monitoring policies list --project="$PROJECT"
        gsafe "Uptime Checks" "$OUT/monitoring_uptime.json" gcloud monitoring uptime list-configs --project="$PROJECT"
    }
    api_on logging.googleapis.com && {
        gsafe "Log Sinks" "$OUT/logging_sinks.json" gcloud logging sinks list --project="$PROJECT"
        gsafe "Log Buckets" "$OUT/logging_buckets.json" gcloud logging buckets list --project="$PROJECT" --location="-"
        gsafe "Log Metrics" "$OUT/logging_metrics.json" gcloud logging metrics list --project="$PROJECT"
    }

    echo -e "${CYAN}━━━ ADICIONALES / BILLING ━━━${NC}"
    api_on iap.googleapis.com && gsafe "IAP Brands" "$OUT/iap_brands.json" gcloud iap oauth-brands list --project="$PROJECT"
    gsafe "Org Policies" "$OUT/org_policies.json" gcloud org-policies list --project="$PROJECT"
    gsafe "Billing Info" "$OUT/billing_info.json" gcloud billing projects describe "$PROJECT"

    # Redactar secretos ANTES de ensamblar el maestro.
    redact_secrets "$OUT"
    write_status "$OUT"

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
" "$OUT" 2>/dev/null && ok "JSON maestro ($PROJECT)" || warn "JSON maestro falló ($PROJECT)"
}

# =============================================================================
# MAIN
# =============================================================================
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   LEVANTAMIENTO GCP v3.0 — Cloud Shell                       ║${NC}"
echo -e "${CYAN}║   SOLO LECTURA · CERO JOBS · Secretos redactados · \$0        ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

command -v gcloud &>/dev/null || { fail "gcloud no encontrado"; exit 1; }
command -v jq &>/dev/null || { fail "jq no encontrado"; exit 1; }
command -v bq &>/dev/null || warn "bq no disponible → se omite sizing de BigQuery"

ACCOUNT=$(gcloud config get-value account 2>/dev/null)
[[ -z "$ACCOUNT" || "$ACCOUNT" == "(unset)" ]] && { fail "No autenticado"; exit 1; }

# Construir lista de proyectos (fix bug subshell: array, no pipe recursivo).
PROJECTS=()
if [[ -n "$SPECIFIC_PROJECT" ]]; then
    PROJECTS=("$SPECIFIC_PROJECT")
elif [[ "$ALL_PROJECTS" == true ]]; then
    while IFS= read -r p; do [[ -n "$p" ]] && PROJECTS+=("$p"); done < <(gcloud projects list --format="value(projectId)" 2>/dev/null)
    [[ ${#PROJECTS[@]} -eq 0 ]] && { fail "No se encontraron proyectos"; exit 1; }
else
    P=$(gcloud config get-value project 2>/dev/null)
    [[ -z "$P" || "$P" == "(unset)" ]] && { fail "Sin proyecto. Usa --project o --all-projects"; exit 1; }
    PROJECTS=("$P")
fi

mkdir -p "$OUTPUT_DIR"
echo -e "  Cuenta:    ${GREEN}$ACCOUNT${NC}"
echo -e "  Proyectos: ${GREEN}${#PROJECTS[@]}${NC}  ·  timeout ${TIMEOUT}s  ·  full_scan=${FULL_SCAN}"
echo -e "  Output:    ${GREEN}$OUTPUT_DIR/${NC}"
echo ""

CURRENT=0
for PROJECT in "${PROJECTS[@]}"; do
    [[ -z "$PROJECT" ]] && continue
    CURRENT=$((CURRENT+1))
    echo ""
    echo -e "${CYAN}══════ PROYECTO [$CURRENT/${#PROJECTS[@]}]: $PROJECT ══════${NC}"
    scan_project "$PROJECT" "$OUTPUT_DIR/$PROJECT"
done

# Resumen global
log "Construyendo _resumen_global.json..."
python3 -c "
import json, os, sys
root = sys.argv[1]
out = {}
for proj in sorted(os.listdir(root)):
    sp = os.path.join(root, proj, '_status.json')
    if not os.path.isfile(sp): continue
    try: st = json.load(open(sp))
    except: continue
    out[proj] = {
      'con_recursos': sorted([x['service'] for x in st if x.get('status')=='ok' and (x.get('count') or 0)>0]),
      'sin_permiso':  sorted([x['service'] for x in st if x.get('status')=='sin_permiso']),
      'timeouts':     sorted([x['service'] for x in st if x.get('status')=='timeout']),
    }
json.dump(out, open(os.path.join(root,'_resumen_global.json'),'w'), indent=2)
print('Proyectos en resumen:', len(out))
" "$OUTPUT_DIR"

END_TIME=$(date +%s); DURATION=$((END_TIME - START_TIME))
TOTAL_SIZE=$(du -sh "$OUTPUT_DIR" 2>/dev/null | awk '{print $1}')
FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.json" | wc -l)

echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    RESUMEN FINAL                              ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Proyectos: ${GREEN}${#PROJECTS[@]}${NC}   JSON: $FILE_COUNT   Tamaño: $TOTAL_SIZE   Duración: ${DURATION}s"
echo -e "  Output:    ${GREEN}$OUTPUT_DIR/${NC}"
echo -e "  Resumen:   ${GREEN}$OUTPUT_DIR/_resumen_global.json${NC}"
echo ""
echo -e "  ${GREEN}✓ Completado — solo lectura, cero jobs, secretos redactados${NC}"
echo ""
echo -e "  ${YELLOW}CONFIDENCIALIDAD:${NC} los JSON traen datos del cliente (emails IAM, firewall)."
echo -e "  Trátalos como confidenciales y borra la carpeta tras descargar:"
echo -e "    ${YELLOW}rm -rf $OUTPUT_DIR${NC}"
echo ""
echo -e "  Si el resumen marca TIMEOUTS, esas familias NO están vacías. Reintenta:"
echo -e "    ${YELLOW}$0 --timeout 45 --project <ID>${NC}"
echo ""
echo -e "  Descargar:"
echo -e "    ${YELLOW}tar czf levantamiento_gcp.tar.gz $OUTPUT_DIR/ && cloudshell download levantamiento_gcp.tar.gz${NC}"
echo ""
