#!/bin/bash
###############################################################################
# SCRIPT DE LEVANTAMIENTO DE INFRAESTRUCTURA AWS
# 
# Descripción: Descubre TODA la infraestructura AWS disponible usando
#              exclusivamente comandos de solo lectura (describe-*, list-*, get-*)
#              Compatible con la política ReadOnlyAccess de AWS.
#
# Requisitos:
#   - AWS CLI v2 configurado con credenciales válidas
#   - jq instalado
#   - Permisos: ReadOnlyAccess (mínimo)
#
# Uso: ./levantamiento-aws.sh [--profile PERFIL] [--output-dir DIRECTORIO]
#
# Autor: Generado para levantamiento de infraestructura
# Fecha: 2024
###############################################################################

set -o pipefail

# =============================================================================
# CONFIGURACIÓN Y VARIABLES GLOBALES
# =============================================================================

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/output/levantamiento_${TIMESTAMP}}"
MASTER_FILE="${OUTPUT_DIR}/infraestructura_completa.json"
TEMP_DIR="${OUTPUT_DIR}/tmp"
AWS_PROFILE_ARG=""
ERRORS_LOG="${OUTPUT_DIR}/errores.log"
SUMMARY_FILE="${OUTPUT_DIR}/resumen.txt"

# Contadores para resumen final
declare -A RESOURCE_COUNTS
TOTAL_ERRORS=0
TOTAL_SERVICES=0
SERVICES_OK=0
SERVICES_FAILED=0

# =============================================================================
# FUNCIONES UTILITARIAS
# =============================================================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # Sin color

# Imprimir progreso a stderr (no contamina stdout/JSON)
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') - $1" >&2
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $(date '+%H:%M:%S') - $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') - $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') - $1" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >> "${ERRORS_LOG}"
    ((TOTAL_ERRORS++))
}

log_section() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════════════════${NC}" >&2
    echo -e "${CYAN}  $1${NC}" >&2
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}" >&2
}

# Ejecutar comando AWS con manejo de errores
# Retorna JSON del resultado o null en caso de error
aws_cmd() {
    local description="$1"
    shift
    local result
    result=$(aws ${AWS_PROFILE_ARG} "$@" 2>>"${ERRORS_LOG}")
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo "$result"
        return 0
    else
        # Verificar si es AccessDenied o servicio no disponible
        if grep -q "AccessDenied\|UnauthorizedOperation\|AuthorizationError" "${ERRORS_LOG}" 2>/dev/null; then
            log_warn "Acceso denegado: ${description}"
        elif grep -q "Could not connect\|EndpointConnectionError\|ServiceNotInRegion" "${ERRORS_LOG}" 2>/dev/null; then
            log_warn "Servicio no disponible: ${description}"
        else
            log_error "Fallo en: ${description}"
        fi
        echo "null"
        return 1
    fi
}

# Ejecutar comando AWS silenciosamente (sin log de error detallado)
aws_cmd_silent() {
    local result
    result=$(aws ${AWS_PROFILE_ARG} "$@" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        echo "$result"
    else
        echo "null"
    fi
}

# Guardar resultado parcial en archivo temporal
save_partial() {
    local service="$1"
    local key="$2"
    local data="$3"
    local file="${TEMP_DIR}/${service}_${key}.json"
    
    if [[ "$data" != "null" && "$data" != "" && "$data" != "[]" && "$data" != "{}" ]]; then
        echo "$data" | jq '.' > "$file" 2>/dev/null
        return 0
    fi
    return 1
}

# Verificar dependencias
check_dependencies() {
    local missing=()
    
    if ! command -v aws &>/dev/null; then
        missing+=("aws-cli")
    fi
    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Dependencias faltantes: ${missing[*]}"
        echo "Instale las dependencias faltantes antes de ejecutar este script." >&2
        exit 1
    fi
}

# Parsear argumentos de línea de comandos
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --profile)
                AWS_PROFILE_ARG="--profile $2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                MASTER_FILE="${OUTPUT_DIR}/infraestructura_completa.json"
                TEMP_DIR="${OUTPUT_DIR}/tmp"
                ERRORS_LOG="${OUTPUT_DIR}/errores.log"
                SUMMARY_FILE="${OUTPUT_DIR}/resumen.txt"
                shift 2
                ;;
            --help|-h)
                echo "Uso: $0 [--profile PERFIL_AWS] [--output-dir DIRECTORIO]"
                echo ""
                echo "Opciones:"
                echo "  --profile     Perfil de AWS CLI a utilizar"
                echo "  --output-dir  Directorio de salida (default: ./output/levantamiento_TIMESTAMP)"
                echo "  --help        Mostrar esta ayuda"
                exit 0
                ;;
            *)
                log_error "Argumento desconocido: $1"
                exit 1
                ;;
        esac
    done
}

# Obtener todas las regiones disponibles
get_all_regions() {
    log_info "Obteniendo lista de regiones disponibles..."
    local regions
    regions=$(aws ${AWS_PROFILE_ARG} ec2 describe-regions \
        --query 'Regions[].RegionName' \
        --output text 2>/dev/null)
    
    if [[ -z "$regions" ]]; then
        # Fallback a regiones conocidas si falla el describe
        regions="us-east-1 us-east-2 us-west-1 us-west-2 eu-west-1 eu-west-2 eu-west-3 eu-central-1 eu-north-1 eu-south-1 ap-southeast-1 ap-southeast-2 ap-northeast-1 ap-northeast-2 ap-northeast-3 ap-south-1 sa-east-1 ca-central-1 me-south-1 af-south-1"
        log_warn "No se pudo obtener regiones dinámicamente, usando lista predeterminada"
    fi
    
    echo "$regions"
}


# =============================================================================
# SERVICIOS GLOBALES (NO REGIONALES)
# =============================================================================

# -----------------------------------------------------------------------------
# IAM - Identity and Access Management (Global)
# -----------------------------------------------------------------------------
discover_iam() {
    log_section "IAM - Identity and Access Management"
    local iam_result="{}"
    
    # Resumen de la cuenta
    log_info "IAM: Obteniendo resumen de cuenta..."
    local summary
    summary=$(aws_cmd "IAM account summary" iam get-account-summary)
    iam_result=$(echo "$iam_result" | jq --argjson v "$summary" '.account_summary = $v')
    
    # Usuarios
    log_info "IAM: Listando usuarios..."
    local users
    users=$(aws_cmd "IAM list users" iam list-users --no-paginate)
    iam_result=$(echo "$iam_result" | jq --argjson v "$users" '.users = $v')
    
    # Para cada usuario, obtener detalles adicionales
    if [[ "$users" != "null" ]]; then
        local user_details="[]"
        local usernames
        usernames=$(echo "$users" | jq -r '.Users[]?.UserName // empty' 2>/dev/null)
        
        while IFS= read -r username; do
            [[ -z "$username" ]] && continue
            log_info "IAM: Detalles del usuario: $username"
            
            # Access keys del usuario
            local access_keys
            access_keys=$(aws_cmd_silent iam list-access-keys --user-name "$username")
            
            # MFA devices
            local mfa
            mfa=$(aws_cmd_silent iam list-mfa-devices --user-name "$username")
            
            # Grupos del usuario
            local user_groups
            user_groups=$(aws_cmd_silent iam list-groups-for-user --user-name "$username")
            
            # Políticas attached
            local user_policies
            user_policies=$(aws_cmd_silent iam list-attached-user-policies --user-name "$username")
            
            # Políticas inline
            local inline_policies
            inline_policies=$(aws_cmd_silent iam list-user-policies --user-name "$username")
            
            # Login profile (si existe)
            local login_profile
            login_profile=$(aws_cmd_silent iam get-login-profile --user-name "$username")
            
            local detail
            detail=$(jq -n \
                --arg name "$username" \
                --argjson keys "$access_keys" \
                --argjson mfa "$mfa" \
                --argjson groups "$user_groups" \
                --argjson policies "$user_policies" \
                --argjson inline "$inline_policies" \
                --argjson login "$login_profile" \
                '{username: $name, access_keys: $keys, mfa_devices: $mfa, groups: $groups, attached_policies: $policies, inline_policies: $inline, login_profile: $login}')
            
            user_details=$(echo "$user_details" | jq --argjson d "$detail" '. += [$d]')
        done <<< "$usernames"
        
        iam_result=$(echo "$iam_result" | jq --argjson v "$user_details" '.user_details = $v')
    fi
    
    # Access keys - last used para todas las keys
    log_info "IAM: Obteniendo último uso de access keys..."
    local all_keys_usage="[]"
    if [[ "$users" != "null" ]]; then
        local all_key_ids
        all_key_ids=$(echo "$iam_result" | jq -r '.user_details[]?.access_keys?.AccessKeyMetadata[]?.AccessKeyId // empty' 2>/dev/null)
        while IFS= read -r key_id; do
            [[ -z "$key_id" ]] && continue
            local key_last_used
            key_last_used=$(aws_cmd_silent iam get-access-key-last-used --access-key-id "$key_id")
            if [[ "$key_last_used" != "null" ]]; then
                all_keys_usage=$(echo "$all_keys_usage" | jq --argjson k "$key_last_used" '. += [$k]')
            fi
        done <<< "$all_key_ids"
    fi
    iam_result=$(echo "$iam_result" | jq --argjson v "$all_keys_usage" '.access_keys_last_used = $v')
    
    # Grupos
    log_info "IAM: Listando grupos..."
    local groups
    groups=$(aws_cmd "IAM list groups" iam list-groups --no-paginate)
    iam_result=$(echo "$iam_result" | jq --argjson v "$groups" '.groups = $v')
    
    # Roles
    log_info "IAM: Listando roles..."
    local roles
    roles=$(aws_cmd "IAM list roles" iam list-roles --no-paginate)
    iam_result=$(echo "$iam_result" | jq --argjson v "$roles" '.roles = $v')
    
    # Políticas (solo customer managed)
    log_info "IAM: Listando políticas (customer managed)..."
    local policies
    policies=$(aws_cmd "IAM list policies" iam list-policies --scope Local --no-paginate)
    iam_result=$(echo "$iam_result" | jq --argjson v "$policies" '.customer_policies = $v')
    
    # Password policy
    log_info "IAM: Obteniendo política de contraseñas..."
    local pwd_policy
    pwd_policy=$(aws_cmd_silent iam get-account-password-policy)
    iam_result=$(echo "$iam_result" | jq --argjson v "$pwd_policy" '.password_policy = $v')
    
    # SAML providers
    log_info "IAM: Listando proveedores SAML..."
    local saml
    saml=$(aws_cmd_silent iam list-saml-providers)
    iam_result=$(echo "$iam_result" | jq --argjson v "$saml" '.saml_providers = $v')
    
    # OpenID Connect providers
    local oidc
    oidc=$(aws_cmd_silent iam list-open-id-connect-providers)
    iam_result=$(echo "$iam_result" | jq --argjson v "$oidc" '.oidc_providers = $v')
    
    save_partial "global" "iam" "$iam_result"
    log_ok "IAM completado"
    ((TOTAL_SERVICES++))
    ((SERVICES_OK++))
}

# -----------------------------------------------------------------------------
# S3 - Simple Storage Service (Global con ubicación por bucket)
# -----------------------------------------------------------------------------
discover_s3() {
    log_section "S3 - Simple Storage Service"
    local s3_result="{}"
    
    # Listar todos los buckets
    log_info "S3: Listando buckets..."
    local buckets
    buckets=$(aws_cmd "S3 list buckets" s3api list-buckets)
    s3_result=$(echo "$s3_result" | jq --argjson v "$buckets" '.buckets = $v')
    
    if [[ "$buckets" != "null" ]]; then
        local bucket_details="[]"
        local bucket_names
        bucket_names=$(echo "$buckets" | jq -r '.Buckets[]?.Name // empty' 2>/dev/null)
        
        while IFS= read -r bucket; do
            [[ -z "$bucket" ]] && continue
            log_info "S3: Analizando bucket: $bucket"
            
            # Ubicación
            local location
            location=$(aws_cmd_silent s3api get-bucket-location --bucket "$bucket")
            
            # Versionado
            local versioning
            versioning=$(aws_cmd_silent s3api get-bucket-versioning --bucket "$bucket")
            
            # Encriptación
            local encryption
            encryption=$(aws_cmd_silent s3api get-bucket-encryption --bucket "$bucket")
            
            # Política del bucket
            local policy
            policy=$(aws_cmd_silent s3api get-bucket-policy --bucket "$bucket")
            
            # ACL
            local acl
            acl=$(aws_cmd_silent s3api get-bucket-acl --bucket "$bucket")
            
            # Lifecycle
            local lifecycle
            lifecycle=$(aws_cmd_silent s3api get-bucket-lifecycle-configuration --bucket "$bucket")
            
            # Tags
            local tags
            tags=$(aws_cmd_silent s3api get-bucket-tagging --bucket "$bucket")
            
            # Website config
            local website
            website=$(aws_cmd_silent s3api get-bucket-website --bucket "$bucket")
            
            # Logging
            local logging
            logging=$(aws_cmd_silent s3api get-bucket-logging --bucket "$bucket")
            
            # Replication
            local replication
            replication=$(aws_cmd_silent s3api get-bucket-replication --bucket "$bucket")
            
            # CORS
            local cors
            cors=$(aws_cmd_silent s3api get-bucket-cors --bucket "$bucket")
            
            # Public access block
            local public_access
            public_access=$(aws_cmd_silent s3api get-public-access-block --bucket "$bucket")
            
            local detail
            detail=$(jq -n \
                --arg name "$bucket" \
                --argjson loc "$location" \
                --argjson ver "$versioning" \
                --argjson enc "$encryption" \
                --argjson pol "$policy" \
                --argjson acl_v "$acl" \
                --argjson lc "$lifecycle" \
                --argjson tg "$tags" \
                --argjson ws "$website" \
                --argjson log "$logging" \
                --argjson rep "$replication" \
                --argjson cors_v "$cors" \
                --argjson pub "$public_access" \
                '{bucket_name: $name, location: $loc, versioning: $ver, encryption: $enc, policy: $pol, acl: $acl_v, lifecycle: $lc, tags: $tg, website: $ws, logging: $log, replication: $rep, cors: $cors_v, public_access_block: $pub}')
            
            bucket_details=$(echo "$bucket_details" | jq --argjson d "$detail" '. += [$d]')
        done <<< "$bucket_names"
        
        s3_result=$(echo "$s3_result" | jq --argjson v "$bucket_details" '.bucket_details = $v')
    fi
    
    save_partial "global" "s3" "$s3_result"
    log_ok "S3 completado"
    ((TOTAL_SERVICES++))
    ((SERVICES_OK++))
}

# -----------------------------------------------------------------------------
# Route53 (Global)
# -----------------------------------------------------------------------------
discover_route53() {
    log_section "Route53 - DNS"
    local r53_result="{}"
    
    log_info "Route53: Listando hosted zones..."
    local zones
    zones=$(aws_cmd "Route53 list zones" route53 list-hosted-zones)
    r53_result=$(echo "$r53_result" | jq --argjson v "$zones" '.hosted_zones = $v')
    
    # Records para cada zona
    if [[ "$zones" != "null" ]]; then
        local zone_details="[]"
        local zone_ids
        zone_ids=$(echo "$zones" | jq -r '.HostedZones[]?.Id // empty' 2>/dev/null)
        
        while IFS= read -r zone_id; do
            [[ -z "$zone_id" ]] && continue
            log_info "Route53: Obteniendo records de zona: $zone_id"
            local records
            records=$(aws_cmd_silent route53 list-resource-record-sets --hosted-zone-id "$zone_id")
            local detail
            detail=$(jq -n --arg id "$zone_id" --argjson r "$records" '{zone_id: $id, records: $r}')
            zone_details=$(echo "$zone_details" | jq --argjson d "$detail" '. += [$d]')
        done <<< "$zone_ids"
        
        r53_result=$(echo "$r53_result" | jq --argjson v "$zone_details" '.zone_records = $v')
    fi
    
    # Health checks
    local health_checks
    health_checks=$(aws_cmd_silent route53 list-health-checks)
    r53_result=$(echo "$r53_result" | jq --argjson v "$health_checks" '.health_checks = $v')
    
    save_partial "global" "route53" "$r53_result"
    log_ok "Route53 completado"
    ((TOTAL_SERVICES++))
    ((SERVICES_OK++))
}

# -----------------------------------------------------------------------------
# CloudFront (Global)
# -----------------------------------------------------------------------------
discover_cloudfront() {
    log_section "CloudFront - CDN"
    local cf_result="{}"
    
    log_info "CloudFront: Listando distribuciones..."
    local distributions
    distributions=$(aws_cmd "CloudFront list distributions" cloudfront list-distributions)
    cf_result=$(echo "$cf_result" | jq --argjson v "$distributions" '.distributions = $v')
    
    save_partial "global" "cloudfront" "$cf_result"
    log_ok "CloudFront completado"
    ((TOTAL_SERVICES++))
    ((SERVICES_OK++))
}

# -----------------------------------------------------------------------------
# WAF v2 (Global - CloudFront scope)
# -----------------------------------------------------------------------------
discover_waf_global() {
    log_section "WAF v2 - Web Application Firewall (Global/CloudFront)"
    local waf_result="{}"
    
    log_info "WAF: Listando Web ACLs (scope CLOUDFRONT)..."
    local web_acls
    web_acls=$(aws_cmd "WAF list web ACLs global" wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1)
    waf_result=$(echo "$waf_result" | jq --argjson v "$web_acls" '.cloudfront_web_acls = $v')
    
    save_partial "global" "waf_global" "$waf_result"
    log_ok "WAF Global completado"
    ((TOTAL_SERVICES++))
    ((SERVICES_OK++))
}

# -----------------------------------------------------------------------------
# Organizations (Global)
# -----------------------------------------------------------------------------
discover_organizations() {
    log_section "Organizations"
    local org_result="{}"
    
    log_info "Organizations: Intentando obtener información de la organización..."
    local org_info
    org_info=$(aws_cmd_silent organizations describe-organization)
    org_result=$(echo "$org_result" | jq --argjson v "$org_info" '.organization = $v')
    
    if [[ "$org_info" != "null" ]]; then
        local accounts
        accounts=$(aws_cmd_silent organizations list-accounts)
        org_result=$(echo "$org_result" | jq --argjson v "$accounts" '.accounts = $v')
        
        local ous
        ous=$(aws_cmd_silent organizations list-roots)
        org_result=$(echo "$org_result" | jq --argjson v "$ous" '.roots = $v')
    fi
    
    save_partial "global" "organizations" "$org_result"
    log_ok "Organizations completado"
    ((TOTAL_SERVICES++))
    ((SERVICES_OK++))
}

# -----------------------------------------------------------------------------
# Cost Explorer (Global - últimos 6 meses)
# -----------------------------------------------------------------------------
discover_cost_explorer() {
    log_section "Cost Explorer - Costos últimos 6 meses"
    local ce_result="{}"
    
    local end_date
    end_date=$(date +%Y-%m-01)
    local start_date
    start_date=$(date -d "6 months ago" +%Y-%m-01 2>/dev/null || date -v-6m +%Y-%m-01 2>/dev/null)
    
    if [[ -z "$start_date" ]]; then
        start_date="2024-01-01"
    fi
    
    log_info "Cost Explorer: Obteniendo costos desde $start_date hasta $end_date..."
    local costs
    costs=$(aws_cmd "Cost Explorer get cost" ce get-cost-and-usage \
        --time-period "Start=${start_date},End=${end_date}" \
        --granularity MONTHLY \
        --metrics "UnblendedCost" "UsageQuantity" \
        --group-by "Type=DIMENSION,Key=SERVICE")
    ce_result=$(echo "$ce_result" | jq --argjson v "$costs" '.monthly_costs_by_service = $v')
    
    # Costo total
    local total_cost
    total_cost=$(aws_cmd_silent ce get-cost-and-usage \
        --time-period "Start=${start_date},End=${end_date}" \
        --granularity MONTHLY \
        --metrics "UnblendedCost")
    ce_result=$(echo "$ce_result" | jq --argjson v "$total_cost" '.monthly_totals = $v')
    
    save_partial "global" "cost_explorer" "$ce_result"
    log_ok "Cost Explorer completado"
    ((TOTAL_SERVICES++))
    ((SERVICES_OK++))
}


# =============================================================================
# SERVICIOS REGIONALES
# =============================================================================

# -----------------------------------------------------------------------------
# EC2 - Elastic Compute Cloud
# -----------------------------------------------------------------------------
discover_ec2() {
    local region="$1"
    local ec2_result="{}"
    
    # Instancias
    log_info "  EC2: Instancias en $region..."
    local instances
    instances=$(aws_cmd_silent ec2 describe-instances --no-paginate --region "$region")
    ec2_result=$(echo "$ec2_result" | jq --argjson v "$instances" '.instances = $v')
    
    # Security Groups
    log_info "  EC2: Security Groups..."
    local sgs
    sgs=$(aws_cmd_silent ec2 describe-security-groups --region "$region")
    ec2_result=$(echo "$ec2_result" | jq --argjson v "$sgs" '.security_groups = $v')
    
    # Key Pairs
    local keypairs
    keypairs=$(aws_cmd_silent ec2 describe-key-pairs --region "$region")
    ec2_result=$(echo "$ec2_result" | jq --argjson v "$keypairs" '.key_pairs = $v')
    
    # Volúmenes EBS
    log_info "  EC2: Volúmenes EBS..."
    local volumes
    volumes=$(aws_cmd_silent ec2 describe-volumes --no-paginate --region "$region")
    ec2_result=$(echo "$ec2_result" | jq --argjson v "$volumes" '.volumes = $v')
    
    # Snapshots (propios)
    log_info "  EC2: Snapshots..."
    local account_id
    account_id=$(aws ${AWS_PROFILE_ARG} sts get-caller-identity --query 'Account' --output text 2>/dev/null)
    local snapshots
    snapshots=$(aws_cmd_silent ec2 describe-snapshots --owner-ids "$account_id" --no-paginate --region "$region")
    ec2_result=$(echo "$ec2_result" | jq --argjson v "$snapshots" '.snapshots = $v')
    
    # AMIs propias
    log_info "  EC2: AMIs propias..."
    local amis
    amis=$(aws_cmd_silent ec2 describe-images --owners self --region "$region")
    ec2_result=$(echo "$ec2_result" | jq --argjson v "$amis" '.amis = $v')
    
    # Elastic IPs
    local eips
    eips=$(aws_cmd_silent ec2 describe-addresses --region "$region")
    ec2_result=$(echo "$ec2_result" | jq --argjson v "$eips" '.elastic_ips = $v')
    
    # Placement Groups
    local pgs
    pgs=$(aws_cmd_silent ec2 describe-placement-groups --region "$region")
    ec2_result=$(echo "$ec2_result" | jq --argjson v "$pgs" '.placement_groups = $v')
    
    # Launch Templates
    log_info "  EC2: Launch Templates..."
    local lts
    lts=$(aws_cmd_silent ec2 describe-launch-templates --region "$region")
    ec2_result=$(echo "$ec2_result" | jq --argjson v "$lts" '.launch_templates = $v')
    
    # Network Interfaces
    local enis
    enis=$(aws_cmd_silent ec2 describe-network-interfaces --region "$region")
    ec2_result=$(echo "$ec2_result" | jq --argjson v "$enis" '.network_interfaces = $v')
    
    echo "$ec2_result"
}

# -----------------------------------------------------------------------------
# VPC - Virtual Private Cloud
# -----------------------------------------------------------------------------
discover_vpc() {
    local region="$1"
    local vpc_result="{}"
    
    # VPCs
    log_info "  VPC: VPCs en $region..."
    local vpcs
    vpcs=$(aws_cmd_silent ec2 describe-vpcs --region "$region")
    vpc_result=$(echo "$vpc_result" | jq --argjson v "$vpcs" '.vpcs = $v')
    
    # Subnets
    local subnets
    subnets=$(aws_cmd_silent ec2 describe-subnets --region "$region")
    vpc_result=$(echo "$vpc_result" | jq --argjson v "$subnets" '.subnets = $v')
    
    # Route Tables
    local rtbs
    rtbs=$(aws_cmd_silent ec2 describe-route-tables --region "$region")
    vpc_result=$(echo "$vpc_result" | jq --argjson v "$rtbs" '.route_tables = $v')
    
    # Internet Gateways
    local igws
    igws=$(aws_cmd_silent ec2 describe-internet-gateways --region "$region")
    vpc_result=$(echo "$vpc_result" | jq --argjson v "$igws" '.internet_gateways = $v')
    
    # NAT Gateways
    local nats
    nats=$(aws_cmd_silent ec2 describe-nat-gateways --region "$region")
    vpc_result=$(echo "$vpc_result" | jq --argjson v "$nats" '.nat_gateways = $v')
    
    # VPC Endpoints
    local endpoints
    endpoints=$(aws_cmd_silent ec2 describe-vpc-endpoints --region "$region")
    vpc_result=$(echo "$vpc_result" | jq --argjson v "$endpoints" '.vpc_endpoints = $v')
    
    # VPC Peering
    local peering
    peering=$(aws_cmd_silent ec2 describe-vpc-peering-connections --region "$region")
    vpc_result=$(echo "$vpc_result" | jq --argjson v "$peering" '.peering_connections = $v')
    
    # Transit Gateways
    local tgws
    tgws=$(aws_cmd_silent ec2 describe-transit-gateways --region "$region")
    vpc_result=$(echo "$vpc_result" | jq --argjson v "$tgws" '.transit_gateways = $v')
    
    # DHCP Options
    local dhcp
    dhcp=$(aws_cmd_silent ec2 describe-dhcp-options --region "$region")
    vpc_result=$(echo "$vpc_result" | jq --argjson v "$dhcp" '.dhcp_options = $v')
    
    # Network ACLs
    local nacls
    nacls=$(aws_cmd_silent ec2 describe-network-acls --region "$region")
    vpc_result=$(echo "$vpc_result" | jq --argjson v "$nacls" '.network_acls = $v')
    
    # VPN Gateways
    local vpn_gws
    vpn_gws=$(aws_cmd_silent ec2 describe-vpn-gateways --region "$region")
    vpc_result=$(echo "$vpc_result" | jq --argjson v "$vpn_gws" '.vpn_gateways = $v')
    
    # VPN Connections
    local vpn_conns
    vpn_conns=$(aws_cmd_silent ec2 describe-vpn-connections --region "$region")
    vpc_result=$(echo "$vpc_result" | jq --argjson v "$vpn_conns" '.vpn_connections = $v')
    
    echo "$vpc_result"
}

# -----------------------------------------------------------------------------
# ELB - Elastic Load Balancing
# -----------------------------------------------------------------------------
discover_elb() {
    local region="$1"
    local elb_result="{}"
    
    # ALBs y NLBs (ELBv2)
    log_info "  ELB: Load Balancers v2 (ALB/NLB)..."
    local elbv2
    elbv2=$(aws_cmd_silent elbv2 describe-load-balancers --region "$region")
    elb_result=$(echo "$elb_result" | jq --argjson v "$elbv2" '.load_balancers_v2 = $v')
    
    # Target Groups
    local tgs
    tgs=$(aws_cmd_silent elbv2 describe-target-groups --region "$region")
    elb_result=$(echo "$elb_result" | jq --argjson v "$tgs" '.target_groups = $v')
    
    # Listeners para cada LB
    if [[ "$elbv2" != "null" ]]; then
        local lb_arns
        lb_arns=$(echo "$elbv2" | jq -r '.LoadBalancers[]?.LoadBalancerArn // empty' 2>/dev/null)
        local all_listeners="[]"
        
        while IFS= read -r lb_arn; do
            [[ -z "$lb_arn" ]] && continue
            local listeners
            listeners=$(aws_cmd_silent elbv2 describe-listeners --load-balancer-arn "$lb_arn" --region "$region")
            if [[ "$listeners" != "null" ]]; then
                all_listeners=$(echo "$all_listeners" | jq --argjson l "$listeners" --arg arn "$lb_arn" '. += [{lb_arn: $arn, listeners: $l}]')
            fi
        done <<< "$lb_arns"
        elb_result=$(echo "$elb_result" | jq --argjson v "$all_listeners" '.listeners = $v')
    fi
    
    # Classic Load Balancers
    log_info "  ELB: Classic Load Balancers..."
    local clbs
    clbs=$(aws_cmd_silent elb describe-load-balancers --region "$region")
    elb_result=$(echo "$elb_result" | jq --argjson v "$clbs" '.classic_load_balancers = $v')
    
    echo "$elb_result"
}


# -----------------------------------------------------------------------------
# ECS - Elastic Container Service
# -----------------------------------------------------------------------------
discover_ecs() {
    local region="$1"
    local ecs_result="{}"
    
    # Clusters
    log_info "  ECS: Clusters..."
    local cluster_arns
    cluster_arns=$(aws_cmd_silent ecs list-clusters --no-paginate --region "$region")
    ecs_result=$(echo "$ecs_result" | jq --argjson v "$cluster_arns" '.cluster_arns = $v')
    
    if [[ "$cluster_arns" != "null" ]]; then
        local arns
        arns=$(echo "$cluster_arns" | jq -r '.clusterArns[]? // empty' 2>/dev/null)
        
        if [[ -n "$arns" ]]; then
            # Describir clusters
            local clusters_desc
            clusters_desc=$(aws_cmd_silent ecs describe-clusters \
                --clusters $(echo "$arns" | tr '\n' ' ') \
                --include ATTACHMENTS SETTINGS STATISTICS TAGS \
                --region "$region")
            ecs_result=$(echo "$ecs_result" | jq --argjson v "$clusters_desc" '.clusters = $v')
            
            # Servicios por cluster
            local all_services="[]"
            while IFS= read -r cluster_arn; do
                [[ -z "$cluster_arn" ]] && continue
                local services
                services=$(aws_cmd_silent ecs list-services --cluster "$cluster_arn" --region "$region")
                if [[ "$services" != "null" ]]; then
                    local svc_arns
                    svc_arns=$(echo "$services" | jq -r '.serviceArns[]? // empty' 2>/dev/null)
                    if [[ -n "$svc_arns" ]]; then
                        local svc_desc
                        svc_desc=$(aws_cmd_silent ecs describe-services \
                            --cluster "$cluster_arn" \
                            --services $(echo "$svc_arns" | tr '\n' ' ') \
                            --region "$region")
                        all_services=$(echo "$all_services" | jq --argjson s "$svc_desc" --arg c "$cluster_arn" '. += [{cluster: $c, services: $s}]')
                    fi
                fi
            done <<< "$arns"
            ecs_result=$(echo "$ecs_result" | jq --argjson v "$all_services" '.services = $v')
            
            # Container Instances
            local all_ci="[]"
            while IFS= read -r cluster_arn; do
                [[ -z "$cluster_arn" ]] && continue
                local ci_list
                ci_list=$(aws_cmd_silent ecs list-container-instances --cluster "$cluster_arn" --region "$region")
                if [[ "$ci_list" != "null" ]]; then
                    all_ci=$(echo "$all_ci" | jq --argjson c "$ci_list" --arg cl "$cluster_arn" '. += [{cluster: $cl, instances: $c}]')
                fi
            done <<< "$arns"
            ecs_result=$(echo "$ecs_result" | jq --argjson v "$all_ci" '.container_instances = $v')
        fi
    fi
    
    # Task Definitions (familias activas)
    log_info "  ECS: Task Definitions..."
    local task_defs
    task_defs=$(aws_cmd_silent ecs list-task-definition-families --status ACTIVE --region "$region")
    ecs_result=$(echo "$ecs_result" | jq --argjson v "$task_defs" '.task_definition_families = $v')
    
    echo "$ecs_result"
}

# -----------------------------------------------------------------------------
# EKS - Elastic Kubernetes Service
# -----------------------------------------------------------------------------
discover_eks() {
    local region="$1"
    local eks_result="{}"
    
    # Clusters
    log_info "  EKS: Clusters..."
    local clusters
    clusters=$(aws_cmd_silent eks list-clusters --region "$region")
    eks_result=$(echo "$eks_result" | jq --argjson v "$clusters" '.cluster_names = $v')
    
    if [[ "$clusters" != "null" ]]; then
        local cluster_names
        cluster_names=$(echo "$clusters" | jq -r '.clusters[]? // empty' 2>/dev/null)
        local cluster_details="[]"
        
        while IFS= read -r cluster_name; do
            [[ -z "$cluster_name" ]] && continue
            log_info "  EKS: Detalles cluster $cluster_name..."
            
            # Describir cluster
            local desc
            desc=$(aws_cmd_silent eks describe-cluster --name "$cluster_name" --region "$region")
            
            # Node groups
            local nodegroups
            nodegroups=$(aws_cmd_silent eks list-nodegroups --cluster-name "$cluster_name" --region "$region")
            
            # Fargate profiles
            local fargate
            fargate=$(aws_cmd_silent eks list-fargate-profiles --cluster-name "$cluster_name" --region "$region")
            
            # Addons
            local addons
            addons=$(aws_cmd_silent eks list-addons --cluster-name "$cluster_name" --region "$region")
            
            local detail
            detail=$(jq -n \
                --arg name "$cluster_name" \
                --argjson desc "$desc" \
                --argjson ng "$nodegroups" \
                --argjson fp "$fargate" \
                --argjson ad "$addons" \
                '{name: $name, cluster: $desc, nodegroups: $ng, fargate_profiles: $fp, addons: $ad}')
            
            cluster_details=$(echo "$cluster_details" | jq --argjson d "$detail" '. += [$d]')
        done <<< "$cluster_names"
        
        eks_result=$(echo "$eks_result" | jq --argjson v "$cluster_details" '.cluster_details = $v')
    fi
    
    echo "$eks_result"
}

# -----------------------------------------------------------------------------
# Lambda
# -----------------------------------------------------------------------------
discover_lambda() {
    local region="$1"
    local lambda_result="{}"
    
    # Funciones
    log_info "  Lambda: Funciones..."
    local functions
    functions=$(aws_cmd_silent lambda list-functions --no-paginate --region "$region")
    lambda_result=$(echo "$lambda_result" | jq --argjson v "$functions" '.functions = $v')
    
    # Detalles de cada función
    if [[ "$functions" != "null" ]]; then
        local func_names
        func_names=$(echo "$functions" | jq -r '.Functions[]?.FunctionName // empty' 2>/dev/null)
        local func_details="[]"
        
        while IFS= read -r func_name; do
            [[ -z "$func_name" ]] && continue
            
            # Configuración completa
            local config
            config=$(aws_cmd_silent lambda get-function-configuration --function-name "$func_name" --region "$region")
            
            # Event source mappings
            local events
            events=$(aws_cmd_silent lambda list-event-source-mappings --function-name "$func_name" --region "$region")
            
            # Tags
            local func_arn
            func_arn=$(echo "$functions" | jq -r --arg n "$func_name" '.Functions[] | select(.FunctionName == $n) | .FunctionArn // empty' 2>/dev/null)
            local tags
            tags=$(aws_cmd_silent lambda list-tags --resource "$func_arn" --region "$region")
            
            local detail
            detail=$(jq -n \
                --arg name "$func_name" \
                --argjson conf "$config" \
                --argjson ev "$events" \
                --argjson tg "$tags" \
                '{name: $name, configuration: $conf, event_sources: $ev, tags: $tg}')
            
            func_details=$(echo "$func_details" | jq --argjson d "$detail" '. += [$d]')
        done <<< "$func_names"
        
        lambda_result=$(echo "$lambda_result" | jq --argjson v "$func_details" '.function_details = $v')
    fi
    
    # Layers
    log_info "  Lambda: Layers..."
    local layers
    layers=$(aws_cmd_silent lambda list-layers --region "$region")
    lambda_result=$(echo "$lambda_result" | jq --argjson v "$layers" '.layers = $v')
    
    echo "$lambda_result"
}


# -----------------------------------------------------------------------------
# RDS - Relational Database Service
# -----------------------------------------------------------------------------
discover_rds() {
    local region="$1"
    local rds_result="{}"
    
    # Instancias
    log_info "  RDS: Instancias..."
    local instances
    instances=$(aws_cmd_silent rds describe-db-instances --no-paginate --region "$region")
    rds_result=$(echo "$rds_result" | jq --argjson v "$instances" '.instances = $v')
    
    # Clusters Aurora
    log_info "  RDS: Clusters Aurora..."
    local clusters
    clusters=$(aws_cmd_silent rds describe-db-clusters --region "$region")
    rds_result=$(echo "$rds_result" | jq --argjson v "$clusters" '.clusters = $v')
    
    # Snapshots
    local snapshots
    snapshots=$(aws_cmd_silent rds describe-db-snapshots --region "$region")
    rds_result=$(echo "$rds_result" | jq --argjson v "$snapshots" '.snapshots = $v')
    
    # Subnet Groups
    local subnet_groups
    subnet_groups=$(aws_cmd_silent rds describe-db-subnet-groups --region "$region")
    rds_result=$(echo "$rds_result" | jq --argjson v "$subnet_groups" '.subnet_groups = $v')
    
    # Parameter Groups
    local param_groups
    param_groups=$(aws_cmd_silent rds describe-db-parameter-groups --region "$region")
    rds_result=$(echo "$rds_result" | jq --argjson v "$param_groups" '.parameter_groups = $v')
    
    # RDS Proxy
    log_info "  RDS: Proxies..."
    local proxies
    proxies=$(aws_cmd_silent rds describe-db-proxies --region "$region")
    rds_result=$(echo "$rds_result" | jq --argjson v "$proxies" '.proxies = $v')
    
    # Reserved instances
    local reserved
    reserved=$(aws_cmd_silent rds describe-reserved-db-instances --region "$region")
    rds_result=$(echo "$rds_result" | jq --argjson v "$reserved" '.reserved_instances = $v')
    
    echo "$rds_result"
}

# -----------------------------------------------------------------------------
# DynamoDB
# -----------------------------------------------------------------------------
discover_dynamodb() {
    local region="$1"
    local ddb_result="{}"
    
    # Listar tablas
    log_info "  DynamoDB: Tablas..."
    local tables
    tables=$(aws_cmd_silent dynamodb list-tables --region "$region")
    ddb_result=$(echo "$ddb_result" | jq --argjson v "$tables" '.table_names = $v')
    
    # Describir cada tabla
    if [[ "$tables" != "null" ]]; then
        local table_names
        table_names=$(echo "$tables" | jq -r '.TableNames[]? // empty' 2>/dev/null)
        local table_details="[]"
        
        while IFS= read -r table_name; do
            [[ -z "$table_name" ]] && continue
            local desc
            desc=$(aws_cmd_silent dynamodb describe-table --table-name "$table_name" --region "$region")
            if [[ "$desc" != "null" ]]; then
                table_details=$(echo "$table_details" | jq --argjson d "$desc" '. += [$d]')
            fi
        done <<< "$table_names"
        
        ddb_result=$(echo "$ddb_result" | jq --argjson v "$table_details" '.table_details = $v')
    fi
    
    # Backups
    local backups
    backups=$(aws_cmd_silent dynamodb list-backups --region "$region")
    ddb_result=$(echo "$ddb_result" | jq --argjson v "$backups" '.backups = $v')
    
    # Global tables
    local global_tables
    global_tables=$(aws_cmd_silent dynamodb list-global-tables --region "$region")
    ddb_result=$(echo "$ddb_result" | jq --argjson v "$global_tables" '.global_tables = $v')
    
    echo "$ddb_result"
}

# -----------------------------------------------------------------------------
# ElastiCache
# -----------------------------------------------------------------------------
discover_elasticache() {
    local region="$1"
    local ec_result="{}"
    
    # Clusters
    log_info "  ElastiCache: Clusters..."
    local clusters
    clusters=$(aws_cmd_silent elasticache describe-cache-clusters --show-cache-node-info --region "$region")
    ec_result=$(echo "$ec_result" | jq --argjson v "$clusters" '.clusters = $v')
    
    # Replication Groups
    local rep_groups
    rep_groups=$(aws_cmd_silent elasticache describe-replication-groups --region "$region")
    ec_result=$(echo "$ec_result" | jq --argjson v "$rep_groups" '.replication_groups = $v')
    
    # Serverless caches
    local serverless
    serverless=$(aws_cmd_silent elasticache describe-serverless-caches --region "$region")
    ec_result=$(echo "$ec_result" | jq --argjson v "$serverless" '.serverless_caches = $v')
    
    # Subnet groups
    local subnet_groups
    subnet_groups=$(aws_cmd_silent elasticache describe-cache-subnet-groups --region "$region")
    ec_result=$(echo "$ec_result" | jq --argjson v "$subnet_groups" '.subnet_groups = $v')
    
    echo "$ec_result"
}


# -----------------------------------------------------------------------------
# SQS - Simple Queue Service
# -----------------------------------------------------------------------------
discover_sqs() {
    local region="$1"
    local sqs_result="{}"
    
    log_info "  SQS: Colas..."
    local queues
    queues=$(aws_cmd_silent sqs list-queues --no-paginate --region "$region")
    sqs_result=$(echo "$sqs_result" | jq --argjson v "$queues" '.queues = $v')
    
    # Atributos de cada cola
    if [[ "$queues" != "null" ]]; then
        local queue_urls
        queue_urls=$(echo "$queues" | jq -r '.QueueUrls[]? // empty' 2>/dev/null)
        local queue_details="[]"
        
        while IFS= read -r queue_url; do
            [[ -z "$queue_url" ]] && continue
            local attrs
            attrs=$(aws_cmd_silent sqs get-queue-attributes --queue-url "$queue_url" --attribute-names All --region "$region")
            local detail
            detail=$(jq -n --arg url "$queue_url" --argjson a "$attrs" '{queue_url: $url, attributes: $a}')
            queue_details=$(echo "$queue_details" | jq --argjson d "$detail" '. += [$d]')
        done <<< "$queue_urls"
        
        sqs_result=$(echo "$sqs_result" | jq --argjson v "$queue_details" '.queue_details = $v')
    fi
    
    echo "$sqs_result"
}

# -----------------------------------------------------------------------------
# SNS - Simple Notification Service
# -----------------------------------------------------------------------------
discover_sns() {
    local region="$1"
    local sns_result="{}"
    
    log_info "  SNS: Topics..."
    local topics
    topics=$(aws_cmd_silent sns list-topics --no-paginate --region "$region")
    sns_result=$(echo "$sns_result" | jq --argjson v "$topics" '.topics = $v')
    
    # Suscripciones
    local subscriptions
    subscriptions=$(aws_cmd_silent sns list-subscriptions --region "$region")
    sns_result=$(echo "$sns_result" | jq --argjson v "$subscriptions" '.subscriptions = $v')
    
    echo "$sns_result"
}

# -----------------------------------------------------------------------------
# API Gateway
# -----------------------------------------------------------------------------
discover_apigateway() {
    local region="$1"
    local apigw_result="{}"
    
    # REST APIs
    log_info "  API Gateway: REST APIs..."
    local rest_apis
    rest_apis=$(aws_cmd_silent apigateway get-rest-apis --region "$region")
    apigw_result=$(echo "$apigw_result" | jq --argjson v "$rest_apis" '.rest_apis = $v')
    
    # Recursos y stages para cada REST API
    if [[ "$rest_apis" != "null" ]]; then
        local api_ids
        api_ids=$(echo "$rest_apis" | jq -r '.items[]?.id // empty' 2>/dev/null)
        local api_details="[]"
        
        while IFS= read -r api_id; do
            [[ -z "$api_id" ]] && continue
            local resources
            resources=$(aws_cmd_silent apigateway get-resources --rest-api-id "$api_id" --region "$region")
            local stages
            stages=$(aws_cmd_silent apigateway get-stages --rest-api-id "$api_id" --region "$region")
            local detail
            detail=$(jq -n --arg id "$api_id" --argjson r "$resources" --argjson s "$stages" '{api_id: $id, resources: $r, stages: $s}')
            api_details=$(echo "$api_details" | jq --argjson d "$detail" '. += [$d]')
        done <<< "$api_ids"
        
        apigw_result=$(echo "$apigw_result" | jq --argjson v "$api_details" '.rest_api_details = $v')
    fi
    
    # HTTP APIs (API Gateway v2)
    log_info "  API Gateway: HTTP/WebSocket APIs..."
    local http_apis
    http_apis=$(aws_cmd_silent apigatewayv2 get-apis --region "$region")
    apigw_result=$(echo "$apigw_result" | jq --argjson v "$http_apis" '.http_websocket_apis = $v')
    
    echo "$apigw_result"
}

# -----------------------------------------------------------------------------
# Step Functions
# -----------------------------------------------------------------------------
discover_stepfunctions() {
    local region="$1"
    local sf_result="{}"
    
    log_info "  Step Functions: State Machines..."
    local machines
    machines=$(aws_cmd_silent stepfunctions list-state-machines --region "$region")
    sf_result=$(echo "$sf_result" | jq --argjson v "$machines" '.state_machines = $v')
    
    echo "$sf_result"
}

# -----------------------------------------------------------------------------
# CloudWatch
# -----------------------------------------------------------------------------
discover_cloudwatch() {
    local region="$1"
    local cw_result="{}"
    
    # Alarmas
    log_info "  CloudWatch: Alarmas..."
    local alarms
    alarms=$(aws_cmd_silent cloudwatch describe-alarms --no-paginate --region "$region")
    cw_result=$(echo "$cw_result" | jq --argjson v "$alarms" '.alarms = $v')
    
    # Log Groups
    log_info "  CloudWatch: Log Groups..."
    local log_groups
    log_groups=$(aws_cmd_silent logs describe-log-groups --no-paginate --region "$region")
    cw_result=$(echo "$cw_result" | jq --argjson v "$log_groups" '.log_groups = $v')
    
    # Dashboards
    local dashboards
    dashboards=$(aws_cmd_silent cloudwatch list-dashboards --region "$region")
    cw_result=$(echo "$cw_result" | jq --argjson v "$dashboards" '.dashboards = $v')
    
    echo "$cw_result"
}

# -----------------------------------------------------------------------------
# Secrets Manager
# -----------------------------------------------------------------------------
discover_secrets_manager() {
    local region="$1"
    local sm_result="{}"
    
    # Solo nombres y ARNs, NO valores
    log_info "  Secrets Manager: Listando secretos (solo metadata)..."
    local secrets
    secrets=$(aws_cmd_silent secretsmanager list-secrets --region "$region")
    sm_result=$(echo "$sm_result" | jq --argjson v "$secrets" '.secrets = $v')
    
    echo "$sm_result"
}

# -----------------------------------------------------------------------------
# KMS - Key Management Service
# -----------------------------------------------------------------------------
discover_kms() {
    local region="$1"
    local kms_result="{}"
    
    log_info "  KMS: Keys..."
    local keys
    keys=$(aws_cmd_silent kms list-keys --region "$region")
    kms_result=$(echo "$kms_result" | jq --argjson v "$keys" '.keys = $v')
    
    # Aliases
    local aliases
    aliases=$(aws_cmd_silent kms list-aliases --region "$region")
    kms_result=$(echo "$kms_result" | jq --argjson v "$aliases" '.aliases = $v')
    
    # Describir cada key
    if [[ "$keys" != "null" ]]; then
        local key_ids
        key_ids=$(echo "$keys" | jq -r '.Keys[]?.KeyId // empty' 2>/dev/null)
        local key_details="[]"
        
        while IFS= read -r key_id; do
            [[ -z "$key_id" ]] && continue
            local desc
            desc=$(aws_cmd_silent kms describe-key --key-id "$key_id" --region "$region")
            if [[ "$desc" != "null" ]]; then
                key_details=$(echo "$key_details" | jq --argjson d "$desc" '. += [$d]')
            fi
        done <<< "$key_ids"
        
        kms_result=$(echo "$kms_result" | jq --argjson v "$key_details" '.key_details = $v')
    fi
    
    echo "$kms_result"
}

# -----------------------------------------------------------------------------
# ACM - Certificate Manager
# -----------------------------------------------------------------------------
discover_acm() {
    local region="$1"
    local acm_result="{}"
    
    log_info "  ACM: Certificados..."
    local certs
    certs=$(aws_cmd_silent acm list-certificates --region "$region")
    acm_result=$(echo "$acm_result" | jq --argjson v "$certs" '.certificates = $v')
    
    # Detalles de cada certificado
    if [[ "$certs" != "null" ]]; then
        local cert_arns
        cert_arns=$(echo "$certs" | jq -r '.CertificateSummaryList[]?.CertificateArn // empty' 2>/dev/null)
        local cert_details="[]"
        
        while IFS= read -r cert_arn; do
            [[ -z "$cert_arn" ]] && continue
            local desc
            desc=$(aws_cmd_silent acm describe-certificate --certificate-arn "$cert_arn" --region "$region")
            if [[ "$desc" != "null" ]]; then
                cert_details=$(echo "$cert_details" | jq --argjson d "$desc" '. += [$d]')
            fi
        done <<< "$cert_arns"
        
        acm_result=$(echo "$acm_result" | jq --argjson v "$cert_details" '.certificate_details = $v')
    fi
    
    echo "$acm_result"
}


# -----------------------------------------------------------------------------
# DMS - Database Migration Service
# -----------------------------------------------------------------------------
discover_dms() {
    local region="$1"
    local dms_result="{}"
    
    log_info "  DMS: Replication Instances..."
    local rep_instances
    rep_instances=$(aws_cmd_silent dms describe-replication-instances --region "$region")
    dms_result=$(echo "$dms_result" | jq --argjson v "$rep_instances" '.replication_instances = $v')
    
    # Endpoints
    local endpoints
    endpoints=$(aws_cmd_silent dms describe-endpoints --region "$region")
    dms_result=$(echo "$dms_result" | jq --argjson v "$endpoints" '.endpoints = $v')
    
    # Tasks
    local tasks
    tasks=$(aws_cmd_silent dms describe-replication-tasks --region "$region")
    dms_result=$(echo "$dms_result" | jq --argjson v "$tasks" '.replication_tasks = $v')
    
    echo "$dms_result"
}

# -----------------------------------------------------------------------------
# Glue
# -----------------------------------------------------------------------------
discover_glue() {
    local region="$1"
    local glue_result="{}"
    
    # Databases
    log_info "  Glue: Databases..."
    local databases
    databases=$(aws_cmd_silent glue get-databases --region "$region")
    glue_result=$(echo "$glue_result" | jq --argjson v "$databases" '.databases = $v')
    
    # Tables por database
    if [[ "$databases" != "null" ]]; then
        local db_names
        db_names=$(echo "$databases" | jq -r '.DatabaseList[]?.Name // empty' 2>/dev/null)
        local all_tables="[]"
        
        while IFS= read -r db_name; do
            [[ -z "$db_name" ]] && continue
            local tables
            tables=$(aws_cmd_silent glue get-tables --database-name "$db_name" --region "$region")
            if [[ "$tables" != "null" ]]; then
                all_tables=$(echo "$all_tables" | jq --argjson t "$tables" --arg db "$db_name" '. += [{database: $db, tables: $t}]')
            fi
        done <<< "$db_names"
        
        glue_result=$(echo "$glue_result" | jq --argjson v "$all_tables" '.tables = $v')
    fi
    
    # Crawlers
    log_info "  Glue: Crawlers..."
    local crawlers
    crawlers=$(aws_cmd_silent glue get-crawlers --region "$region")
    glue_result=$(echo "$glue_result" | jq --argjson v "$crawlers" '.crawlers = $v')
    
    # Jobs
    log_info "  Glue: Jobs..."
    local jobs
    jobs=$(aws_cmd_silent glue get-jobs --region "$region")
    glue_result=$(echo "$glue_result" | jq --argjson v "$jobs" '.jobs = $v')
    
    echo "$glue_result"
}

# -----------------------------------------------------------------------------
# Athena
# -----------------------------------------------------------------------------
discover_athena() {
    local region="$1"
    local athena_result="{}"
    
    log_info "  Athena: Workgroups..."
    local workgroups
    workgroups=$(aws_cmd_silent athena list-work-groups --region "$region")
    athena_result=$(echo "$athena_result" | jq --argjson v "$workgroups" '.workgroups = $v')
    
    # Named queries
    local queries
    queries=$(aws_cmd_silent athena list-named-queries --region "$region")
    athena_result=$(echo "$athena_result" | jq --argjson v "$queries" '.named_queries = $v')
    
    echo "$athena_result"
}

# -----------------------------------------------------------------------------
# Kinesis
# -----------------------------------------------------------------------------
discover_kinesis() {
    local region="$1"
    local kinesis_result="{}"
    
    log_info "  Kinesis: Streams..."
    local streams
    streams=$(aws_cmd_silent kinesis list-streams --region "$region")
    kinesis_result=$(echo "$kinesis_result" | jq --argjson v "$streams" '.streams = $v')
    
    # Describir cada stream
    if [[ "$streams" != "null" ]]; then
        local stream_names
        stream_names=$(echo "$streams" | jq -r '.StreamNames[]? // empty' 2>/dev/null)
        local stream_details="[]"
        
        while IFS= read -r stream_name; do
            [[ -z "$stream_name" ]] && continue
            local desc
            desc=$(aws_cmd_silent kinesis describe-stream-summary --stream-name "$stream_name" --region "$region")
            if [[ "$desc" != "null" ]]; then
                stream_details=$(echo "$stream_details" | jq --argjson d "$desc" '. += [$d]')
            fi
        done <<< "$stream_names"
        
        kinesis_result=$(echo "$kinesis_result" | jq --argjson v "$stream_details" '.stream_details = $v')
    fi
    
    echo "$kinesis_result"
}

# -----------------------------------------------------------------------------
# MSK - Managed Streaming for Apache Kafka
# -----------------------------------------------------------------------------
discover_msk() {
    local region="$1"
    local msk_result="{}"
    
    log_info "  MSK: Clusters..."
    local clusters
    clusters=$(aws_cmd_silent kafka list-clusters-v2 --region "$region")
    msk_result=$(echo "$msk_result" | jq --argjson v "$clusters" '.clusters = $v')
    
    echo "$msk_result"
}

# -----------------------------------------------------------------------------
# EventBridge
# -----------------------------------------------------------------------------
discover_eventbridge() {
    local region="$1"
    local eb_result="{}"
    
    # Event Buses
    log_info "  EventBridge: Event Buses..."
    local buses
    buses=$(aws_cmd_silent events list-event-buses --region "$region")
    eb_result=$(echo "$eb_result" | jq --argjson v "$buses" '.event_buses = $v')
    
    # Rules (default bus)
    local rules
    rules=$(aws_cmd_silent events list-rules --region "$region")
    eb_result=$(echo "$eb_result" | jq --argjson v "$rules" '.rules = $v')
    
    echo "$eb_result"
}

# -----------------------------------------------------------------------------
# WAF v2 (Regional)
# -----------------------------------------------------------------------------
discover_waf_regional() {
    local region="$1"
    local waf_result="{}"
    
    log_info "  WAF: Web ACLs (regional)..."
    local web_acls
    web_acls=$(aws_cmd_silent wafv2 list-web-acls --scope REGIONAL --region "$region")
    waf_result=$(echo "$waf_result" | jq --argjson v "$web_acls" '.web_acls = $v')
    
    # IP Sets
    local ip_sets
    ip_sets=$(aws_cmd_silent wafv2 list-ip-sets --scope REGIONAL --region "$region")
    waf_result=$(echo "$waf_result" | jq --argjson v "$ip_sets" '.ip_sets = $v')
    
    echo "$waf_result"
}


# -----------------------------------------------------------------------------
# CodePipeline
# -----------------------------------------------------------------------------
discover_codepipeline() {
    local region="$1"
    local cp_result="{}"
    
    log_info "  CodePipeline: Pipelines..."
    local pipelines
    pipelines=$(aws_cmd_silent codepipeline list-pipelines --region "$region")
    cp_result=$(echo "$cp_result" | jq --argjson v "$pipelines" '.pipelines = $v')
    
    echo "$cp_result"
}

# -----------------------------------------------------------------------------
# CodeBuild
# -----------------------------------------------------------------------------
discover_codebuild() {
    local region="$1"
    local cb_result="{}"
    
    log_info "  CodeBuild: Projects..."
    local projects
    projects=$(aws_cmd_silent codebuild list-projects --region "$region")
    cb_result=$(echo "$cb_result" | jq --argjson v "$projects" '.projects = $v')
    
    # Describir proyectos
    if [[ "$projects" != "null" ]]; then
        local project_names
        project_names=$(echo "$projects" | jq -r '.projects[]? // empty' 2>/dev/null)
        if [[ -n "$project_names" ]]; then
            local proj_desc
            proj_desc=$(aws_cmd_silent codebuild batch-get-projects --names $(echo "$project_names" | tr '\n' ' ') --region "$region")
            cb_result=$(echo "$cb_result" | jq --argjson v "$proj_desc" '.project_details = $v')
        fi
    fi
    
    echo "$cb_result"
}

# -----------------------------------------------------------------------------
# CodeDeploy
# -----------------------------------------------------------------------------
discover_codedeploy() {
    local region="$1"
    local cd_result="{}"
    
    log_info "  CodeDeploy: Applications..."
    local apps
    apps=$(aws_cmd_silent deploy list-applications --region "$region")
    cd_result=$(echo "$cd_result" | jq --argjson v "$apps" '.applications = $v')
    
    # Deployment groups
    if [[ "$apps" != "null" ]]; then
        local app_names
        app_names=$(echo "$apps" | jq -r '.applications[]? // empty' 2>/dev/null)
        local all_groups="[]"
        
        while IFS= read -r app_name; do
            [[ -z "$app_name" ]] && continue
            local groups
            groups=$(aws_cmd_silent deploy list-deployment-groups --application-name "$app_name" --region "$region")
            if [[ "$groups" != "null" ]]; then
                all_groups=$(echo "$all_groups" | jq --argjson g "$groups" --arg app "$app_name" '. += [{application: $app, groups: $g}]')
            fi
        done <<< "$app_names"
        
        cd_result=$(echo "$cd_result" | jq --argjson v "$all_groups" '.deployment_groups = $v')
    fi
    
    echo "$cd_result"
}

# -----------------------------------------------------------------------------
# ECR - Elastic Container Registry
# -----------------------------------------------------------------------------
discover_ecr() {
    local region="$1"
    local ecr_result="{}"
    
    log_info "  ECR: Repositorios..."
    local repos
    repos=$(aws_cmd_silent ecr describe-repositories --region "$region")
    ecr_result=$(echo "$ecr_result" | jq --argjson v "$repos" '.repositories = $v')
    
    # Imágenes por repositorio
    if [[ "$repos" != "null" ]]; then
        local repo_names
        repo_names=$(echo "$repos" | jq -r '.repositories[]?.repositoryName // empty' 2>/dev/null)
        local all_images="[]"
        
        while IFS= read -r repo_name; do
            [[ -z "$repo_name" ]] && continue
            local images
            images=$(aws_cmd_silent ecr list-images --repository-name "$repo_name" --region "$region")
            if [[ "$images" != "null" ]]; then
                all_images=$(echo "$all_images" | jq --argjson i "$images" --arg r "$repo_name" '. += [{repository: $r, images: $i}]')
            fi
        done <<< "$repo_names"
        
        ecr_result=$(echo "$ecr_result" | jq --argjson v "$all_images" '.images = $v')
    fi
    
    echo "$ecr_result"
}

# -----------------------------------------------------------------------------
# EFS - Elastic File System
# -----------------------------------------------------------------------------
discover_efs() {
    local region="$1"
    local efs_result="{}"
    
    log_info "  EFS: File Systems..."
    local filesystems
    filesystems=$(aws_cmd_silent efs describe-file-systems --region "$region")
    efs_result=$(echo "$efs_result" | jq --argjson v "$filesystems" '.file_systems = $v')
    
    # Mount targets por filesystem
    if [[ "$filesystems" != "null" ]]; then
        local fs_ids
        fs_ids=$(echo "$filesystems" | jq -r '.FileSystems[]?.FileSystemId // empty' 2>/dev/null)
        local all_mounts="[]"
        
        while IFS= read -r fs_id; do
            [[ -z "$fs_id" ]] && continue
            local mounts
            mounts=$(aws_cmd_silent efs describe-mount-targets --file-system-id "$fs_id" --region "$region")
            if [[ "$mounts" != "null" ]]; then
                all_mounts=$(echo "$all_mounts" | jq --argjson m "$mounts" --arg id "$fs_id" '. += [{file_system_id: $id, mount_targets: $m}]')
            fi
        done <<< "$fs_ids"
        
        efs_result=$(echo "$efs_result" | jq --argjson v "$all_mounts" '.mount_targets = $v')
    fi
    
    echo "$efs_result"
}

# -----------------------------------------------------------------------------
# DocumentDB
# -----------------------------------------------------------------------------
discover_documentdb() {
    local region="$1"
    local docdb_result="{}"
    
    log_info "  DocumentDB: Clusters..."
    local clusters
    clusters=$(aws_cmd_silent docdb describe-db-clusters \
        --filters "Name=engine,Values=docdb" --region "$region")
    docdb_result=$(echo "$docdb_result" | jq --argjson v "$clusters" '.clusters = $v')
    
    # Instancias
    local instances
    instances=$(aws_cmd_silent docdb describe-db-instances \
        --filters "Name=engine,Values=docdb" --region "$region")
    docdb_result=$(echo "$docdb_result" | jq --argjson v "$instances" '.instances = $v')
    
    echo "$docdb_result"
}

# -----------------------------------------------------------------------------
# MQ - Amazon MQ (ActiveMQ/RabbitMQ)
# -----------------------------------------------------------------------------
discover_mq() {
    local region="$1"
    local mq_result="{}"
    
    log_info "  MQ: Brokers..."
    local brokers
    brokers=$(aws_cmd_silent mq list-brokers --region "$region")
    mq_result=$(echo "$mq_result" | jq --argjson v "$brokers" '.brokers = $v')
    
    echo "$mq_result"
}

# -----------------------------------------------------------------------------
# Backup
# -----------------------------------------------------------------------------
discover_backup() {
    local region="$1"
    local backup_result="{}"
    
    # Planes de backup
    log_info "  Backup: Planes..."
    local plans
    plans=$(aws_cmd_silent backup list-backup-plans --region "$region")
    backup_result=$(echo "$backup_result" | jq --argjson v "$plans" '.backup_plans = $v')
    
    # Vaults
    log_info "  Backup: Vaults..."
    local vaults
    vaults=$(aws_cmd_silent backup list-backup-vaults --region "$region")
    backup_result=$(echo "$backup_result" | jq --argjson v "$vaults" '.backup_vaults = $v')
    
    echo "$backup_result"
}


# -----------------------------------------------------------------------------
# CloudTrail
# -----------------------------------------------------------------------------
discover_cloudtrail() {
    local region="$1"
    local ct_result="{}"
    
    log_info "  CloudTrail: Trails..."
    local trails
    trails=$(aws_cmd_silent cloudtrail describe-trails --region "$region")
    ct_result=$(echo "$ct_result" | jq --argjson v "$trails" '.trails = $v')
    
    # Estado de cada trail
    if [[ "$trails" != "null" ]]; then
        local trail_arns
        trail_arns=$(echo "$trails" | jq -r '.trailList[]?.TrailARN // empty' 2>/dev/null)
        local trail_status="[]"
        
        while IFS= read -r trail_arn; do
            [[ -z "$trail_arn" ]] && continue
            local status
            status=$(aws_cmd_silent cloudtrail get-trail-status --name "$trail_arn" --region "$region")
            if [[ "$status" != "null" ]]; then
                trail_status=$(echo "$trail_status" | jq --argjson s "$status" --arg arn "$trail_arn" '. += [{trail_arn: $arn, status: $s}]')
            fi
        done <<< "$trail_arns"
        
        ct_result=$(echo "$ct_result" | jq --argjson v "$trail_status" '.trail_status = $v')
    fi
    
    echo "$ct_result"
}

# -----------------------------------------------------------------------------
# AWS Config
# -----------------------------------------------------------------------------
discover_config() {
    local region="$1"
    local config_result="{}"
    
    log_info "  Config: Recorders..."
    local recorders
    recorders=$(aws_cmd_silent configservice describe-configuration-recorders --region "$region")
    config_result=$(echo "$config_result" | jq --argjson v "$recorders" '.recorders = $v')
    
    # Recorder status
    local recorder_status
    recorder_status=$(aws_cmd_silent configservice describe-configuration-recorder-status --region "$region")
    config_result=$(echo "$config_result" | jq --argjson v "$recorder_status" '.recorder_status = $v')
    
    # Config rules
    local rules
    rules=$(aws_cmd_silent configservice describe-config-rules --region "$region")
    config_result=$(echo "$config_result" | jq --argjson v "$rules" '.config_rules = $v')
    
    echo "$config_result"
}

# -----------------------------------------------------------------------------
# GuardDuty
# -----------------------------------------------------------------------------
discover_guardduty() {
    local region="$1"
    local gd_result="{}"
    
    log_info "  GuardDuty: Detectors..."
    local detectors
    detectors=$(aws_cmd_silent guardduty list-detectors --region "$region")
    gd_result=$(echo "$gd_result" | jq --argjson v "$detectors" '.detectors = $v')
    
    # Detalles de cada detector
    if [[ "$detectors" != "null" ]]; then
        local det_ids
        det_ids=$(echo "$detectors" | jq -r '.DetectorIds[]? // empty' 2>/dev/null)
        local det_details="[]"
        
        while IFS= read -r det_id; do
            [[ -z "$det_id" ]] && continue
            local desc
            desc=$(aws_cmd_silent guardduty get-detector --detector-id "$det_id" --region "$region")
            if [[ "$desc" != "null" ]]; then
                det_details=$(echo "$det_details" | jq --argjson d "$desc" '. += [$d]')
            fi
        done <<< "$det_ids"
        
        gd_result=$(echo "$gd_result" | jq --argjson v "$det_details" '.detector_details = $v')
    fi
    
    echo "$gd_result"
}

# -----------------------------------------------------------------------------
# Security Hub
# -----------------------------------------------------------------------------
discover_securityhub() {
    local region="$1"
    local sh_result="{}"
    
    log_info "  Security Hub: Estado..."
    local hub
    hub=$(aws_cmd_silent securityhub describe-hub --region "$region")
    sh_result=$(echo "$sh_result" | jq --argjson v "$hub" '.hub = $v')
    
    if [[ "$hub" != "null" ]]; then
        # Standards habilitados
        local standards
        standards=$(aws_cmd_silent securityhub get-enabled-standards --region "$region")
        sh_result=$(echo "$sh_result" | jq --argjson v "$standards" '.enabled_standards = $v')
    fi
    
    echo "$sh_result"
}

# -----------------------------------------------------------------------------
# Auto Scaling
# -----------------------------------------------------------------------------
discover_autoscaling() {
    local region="$1"
    local as_result="{}"
    
    log_info "  Auto Scaling: Groups..."
    local groups
    groups=$(aws_cmd_silent autoscaling describe-auto-scaling-groups --region "$region")
    as_result=$(echo "$as_result" | jq --argjson v "$groups" '.auto_scaling_groups = $v')
    
    # Launch configurations
    local launch_configs
    launch_configs=$(aws_cmd_silent autoscaling describe-launch-configurations --region "$region")
    as_result=$(echo "$as_result" | jq --argjson v "$launch_configs" '.launch_configurations = $v')
    
    # Scaling policies
    local policies
    policies=$(aws_cmd_silent autoscaling describe-policies --region "$region")
    as_result=$(echo "$as_result" | jq --argjson v "$policies" '.scaling_policies = $v')
    
    echo "$as_result"
}

# -----------------------------------------------------------------------------
# CloudFormation
# -----------------------------------------------------------------------------
discover_cloudformation() {
    local region="$1"
    local cfn_result="{}"
    
    log_info "  CloudFormation: Stacks..."
    local stacks
    stacks=$(aws_cmd_silent cloudformation describe-stacks --region "$region")
    cfn_result=$(echo "$cfn_result" | jq --argjson v "$stacks" '.stacks = $v')
    
    echo "$cfn_result"
}


# -----------------------------------------------------------------------------
# Cognito
# -----------------------------------------------------------------------------
discover_cognito() {
    local region="$1"
    local cognito_result="{}"
    
    log_info "  Cognito: User Pools..."
    local user_pools
    user_pools=$(aws_cmd_silent cognito-idp list-user-pools --max-results 60 --region "$region")
    cognito_result=$(echo "$cognito_result" | jq --argjson v "$user_pools" '.user_pools = $v')
    
    log_info "  Cognito: Identity Pools..."
    local identity_pools
    identity_pools=$(aws_cmd_silent cognito-identity list-identity-pools --max-results 60 --region "$region")
    cognito_result=$(echo "$cognito_result" | jq --argjson v "$identity_pools" '.identity_pools = $v')
    
    echo "$cognito_result"
}

# -----------------------------------------------------------------------------
# OpenSearch
# -----------------------------------------------------------------------------
discover_opensearch() {
    local region="$1"
    local opensearch_result="{}"
    
    log_info "  OpenSearch: Dominios..."
    local domain_names
    domain_names=$(aws_cmd_silent opensearch list-domain-names --region "$region")
    opensearch_result=$(echo "$opensearch_result" | jq --argjson v "$domain_names" '.domain_names = $v')
    
    # Describir cada dominio
    if [[ "$domain_names" != "null" ]]; then
        local names
        names=$(echo "$domain_names" | jq -r '.DomainNames[]?.DomainName // empty' 2>/dev/null)
        local domain_details="[]"
        
        while IFS= read -r dname; do
            [[ -z "$dname" ]] && continue
            local desc
            desc=$(aws_cmd_silent opensearch describe-domain --domain-name "$dname" --region "$region")
            if [[ "$desc" != "null" ]]; then
                domain_details=$(echo "$domain_details" | jq --argjson d "$desc" '. += [$d]')
            fi
        done <<< "$names"
        
        opensearch_result=$(echo "$opensearch_result" | jq --argjson v "$domain_details" '.domain_details = $v')
    fi
    
    echo "$opensearch_result"
}

# -----------------------------------------------------------------------------
# Redshift
# -----------------------------------------------------------------------------
discover_redshift() {
    local region="$1"
    local redshift_result="{}"
    
    log_info "  Redshift: Clusters..."
    local clusters
    clusters=$(aws_cmd_silent redshift describe-clusters --region "$region")
    redshift_result=$(echo "$redshift_result" | jq --argjson v "$clusters" '.clusters = $v')
    
    echo "$redshift_result"
}

# -----------------------------------------------------------------------------
# SES - Simple Email Service
# -----------------------------------------------------------------------------
discover_ses() {
    local region="$1"
    local ses_result="{}"
    
    log_info "  SES: Email Identities..."
    local identities
    identities=$(aws_cmd_silent sesv2 list-email-identities --region "$region")
    ses_result=$(echo "$ses_result" | jq --argjson v "$identities" '.email_identities = $v')
    
    log_info "  SES: Account info..."
    local account
    account=$(aws_cmd_silent sesv2 get-account --region "$region")
    ses_result=$(echo "$ses_result" | jq --argjson v "$account" '.account = $v')
    
    echo "$ses_result"
}

# -----------------------------------------------------------------------------
# App Runner
# -----------------------------------------------------------------------------
discover_apprunner() {
    local region="$1"
    local apprunner_result="{}"
    
    log_info "  App Runner: Services..."
    local services
    services=$(aws_cmd_silent apprunner list-services --region "$region")
    apprunner_result=$(echo "$apprunner_result" | jq --argjson v "$services" '.services = $v')
    
    echo "$apprunner_result"
}

# -----------------------------------------------------------------------------
# Amplify
# -----------------------------------------------------------------------------
discover_amplify() {
    local region="$1"
    local amplify_result="{}"
    
    log_info "  Amplify: Apps..."
    local apps
    apps=$(aws_cmd_silent amplify list-apps --region "$region")
    amplify_result=$(echo "$amplify_result" | jq --argjson v "$apps" '.apps = $v')
    
    echo "$amplify_result"
}

# -----------------------------------------------------------------------------
# Transfer Family
# -----------------------------------------------------------------------------
discover_transfer() {
    local region="$1"
    local transfer_result="{}"
    
    log_info "  Transfer Family: Servers..."
    local servers
    servers=$(aws_cmd_silent transfer list-servers --region "$region")
    transfer_result=$(echo "$transfer_result" | jq --argjson v "$servers" '.servers = $v')
    
    echo "$transfer_result"
}


# =============================================================================
# FUNCIÓN PRINCIPAL DE DESCUBRIMIENTO REGIONAL
# =============================================================================

discover_region() {
    local region="$1"
    local region_result="{}"
    
    log_section "REGIÓN: $region"
    
    # EC2
    local ec2_data
    ec2_data=$(discover_ec2 "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$ec2_data" '.ec2 = $v')
    
    # VPC
    local vpc_data
    vpc_data=$(discover_vpc "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$vpc_data" '.vpc = $v')
    
    # ELB
    local elb_data
    elb_data=$(discover_elb "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$elb_data" '.elb = $v')
    
    # ECS
    local ecs_data
    ecs_data=$(discover_ecs "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$ecs_data" '.ecs = $v')
    
    # EKS
    local eks_data
    eks_data=$(discover_eks "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$eks_data" '.eks = $v')
    
    # Lambda
    local lambda_data
    lambda_data=$(discover_lambda "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$lambda_data" '.lambda = $v')
    
    # RDS
    local rds_data
    rds_data=$(discover_rds "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$rds_data" '.rds = $v')
    
    # DynamoDB
    local ddb_data
    ddb_data=$(discover_dynamodb "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$ddb_data" '.dynamodb = $v')
    
    # ElastiCache
    local ec_data
    ec_data=$(discover_elasticache "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$ec_data" '.elasticache = $v')
    
    # SQS
    local sqs_data
    sqs_data=$(discover_sqs "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$sqs_data" '.sqs = $v')
    
    # SNS
    local sns_data
    sns_data=$(discover_sns "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$sns_data" '.sns = $v')
    
    # API Gateway
    local apigw_data
    apigw_data=$(discover_apigateway "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$apigw_data" '.api_gateway = $v')
    
    # Step Functions
    local sf_data
    sf_data=$(discover_stepfunctions "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$sf_data" '.step_functions = $v')
    
    # CloudWatch
    local cw_data
    cw_data=$(discover_cloudwatch "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$cw_data" '.cloudwatch = $v')
    
    # Secrets Manager
    local sm_data
    sm_data=$(discover_secrets_manager "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$sm_data" '.secrets_manager = $v')
    
    # KMS
    local kms_data
    kms_data=$(discover_kms "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$kms_data" '.kms = $v')
    
    # WAF Regional
    local waf_data
    waf_data=$(discover_waf_regional "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$waf_data" '.waf = $v')
    
    # ACM
    local acm_data
    acm_data=$(discover_acm "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$acm_data" '.acm = $v')
    
    # DMS
    local dms_data
    dms_data=$(discover_dms "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$dms_data" '.dms = $v')
    
    # Glue
    local glue_data
    glue_data=$(discover_glue "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$glue_data" '.glue = $v')
    
    # Athena
    local athena_data
    athena_data=$(discover_athena "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$athena_data" '.athena = $v')
    
    # Kinesis
    local kinesis_data
    kinesis_data=$(discover_kinesis "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$kinesis_data" '.kinesis = $v')
    
    # MSK
    local msk_data
    msk_data=$(discover_msk "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$msk_data" '.msk = $v')
    
    # EventBridge
    local eb_data
    eb_data=$(discover_eventbridge "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$eb_data" '.eventbridge = $v')
    
    # CodePipeline
    local cp_data
    cp_data=$(discover_codepipeline "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$cp_data" '.codepipeline = $v')
    
    # CodeBuild
    local cb_data
    cb_data=$(discover_codebuild "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$cb_data" '.codebuild = $v')
    
    # CodeDeploy
    local cd_data
    cd_data=$(discover_codedeploy "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$cd_data" '.codedeploy = $v')
    
    # ECR
    local ecr_data
    ecr_data=$(discover_ecr "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$ecr_data" '.ecr = $v')
    
    # EFS
    local efs_data
    efs_data=$(discover_efs "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$efs_data" '.efs = $v')
    
    # DocumentDB
    local docdb_data
    docdb_data=$(discover_documentdb "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$docdb_data" '.documentdb = $v')
    
    # MQ
    local mq_data
    mq_data=$(discover_mq "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$mq_data" '.mq = $v')
    
    # Backup
    local backup_data
    backup_data=$(discover_backup "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$backup_data" '.backup = $v')
    
    # CloudTrail
    local ct_data
    ct_data=$(discover_cloudtrail "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$ct_data" '.cloudtrail = $v')
    
    # Config
    local config_data
    config_data=$(discover_config "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$config_data" '.config = $v')
    
    # GuardDuty
    local gd_data
    gd_data=$(discover_guardduty "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$gd_data" '.guardduty = $v')
    
    # Security Hub
    local sh_data
    sh_data=$(discover_securityhub "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$sh_data" '.securityhub = $v')
    
    # Auto Scaling
    local as_data
    as_data=$(discover_autoscaling "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$as_data" '.autoscaling = $v')
    
    # CloudFormation
    local cfn_data
    cfn_data=$(discover_cloudformation "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$cfn_data" '.cloudformation = $v')
    
    # Cognito
    local cognito_data
    cognito_data=$(discover_cognito "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$cognito_data" '.cognito = $v')
    
    # OpenSearch
    local opensearch_data
    opensearch_data=$(discover_opensearch "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$opensearch_data" '.opensearch = $v')
    
    # Redshift
    local redshift_data
    redshift_data=$(discover_redshift "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$redshift_data" '.redshift = $v')
    
    # SES
    local ses_data
    ses_data=$(discover_ses "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$ses_data" '.ses = $v')
    
    # App Runner
    local apprunner_data
    apprunner_data=$(discover_apprunner "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$apprunner_data" '.apprunner = $v')
    
    # Amplify
    local amplify_data
    amplify_data=$(discover_amplify "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$amplify_data" '.amplify = $v')
    
    # Transfer Family
    local transfer_data
    transfer_data=$(discover_transfer "$region")
    region_result=$(echo "$region_result" | jq --argjson v "$transfer_data" '.transfer = $v')
    
    # Guardar resultado de la región
    save_partial "regions" "$region" "$region_result"
    log_ok "Región $region completada"
}


# =============================================================================
# FUNCIÓN DE ENSAMBLAJE FINAL
# =============================================================================

assemble_final_json() {
    log_section "ENSAMBLANDO RESULTADO FINAL"
    
    local final_json="{}"
    
    # Metadata del levantamiento
    local account_id
    account_id=$(aws ${AWS_PROFILE_ARG} sts get-caller-identity --query 'Account' --output text 2>/dev/null)
    local caller_arn
    caller_arn=$(aws ${AWS_PROFILE_ARG} sts get-caller-identity --query 'Arn' --output text 2>/dev/null)
    local user_id
    user_id=$(aws ${AWS_PROFILE_ARG} sts get-caller-identity --query 'UserId' --output text 2>/dev/null)
    
    local metadata
    metadata=$(jq -n \
        --arg ts "$TIMESTAMP" \
        --arg dt "$(date -Iseconds)" \
        --arg account "$account_id" \
        --arg caller "$caller_arn" \
        --arg userid "$user_id" \
        --arg script_version "1.0.0" \
        '{
            timestamp: $ts,
            datetime: $dt,
            account_id: $account,
            caller_identity: $caller,
            user_id: $userid,
            script_version: $script_version
        }')
    
    final_json=$(echo "$final_json" | jq --argjson v "$metadata" '.metadata = $v')
    
    # Agregar servicios globales
    log_info "Agregando servicios globales..."
    local global_services="{}"
    
    for f in "${TEMP_DIR}"/global_*.json; do
        [[ -f "$f" ]] || continue
        local key
        key=$(basename "$f" .json | sed 's/^global_//')
        local content
        content=$(cat "$f")
        global_services=$(echo "$global_services" | jq --argjson v "$content" --arg k "$key" '.[$k] = $v')
    done
    
    final_json=$(echo "$final_json" | jq --argjson v "$global_services" '.global_services = $v')
    
    # Agregar datos regionales
    log_info "Agregando datos regionales..."
    local regional_data="{}"
    
    for f in "${TEMP_DIR}"/regions_*.json; do
        [[ -f "$f" ]] || continue
        local region_name
        region_name=$(basename "$f" .json | sed 's/^regions_//')
        local content
        content=$(cat "$f")
        regional_data=$(echo "$regional_data" | jq --argjson v "$content" --arg k "$region_name" '.[$k] = $v')
    done
    
    final_json=$(echo "$final_json" | jq --argjson v "$regional_data" '.regional_services = $v')
    
    # Escribir archivo final
    echo "$final_json" | jq '.' > "$MASTER_FILE"
    
    log_ok "Archivo final generado: $MASTER_FILE"
    log_info "Tamaño: $(du -h "$MASTER_FILE" | cut -f1)"
}

# =============================================================================
# GENERAR RESUMEN
# =============================================================================

generate_summary() {
    log_section "RESUMEN DEL LEVANTAMIENTO"
    
    local file_size
    file_size=$(du -h "$MASTER_FILE" | cut -f1)
    
    {
        echo "=============================================="
        echo " RESUMEN DE LEVANTAMIENTO AWS"
        echo "=============================================="
        echo ""
        echo "Fecha: $(date)"
        echo "Archivo de salida: $MASTER_FILE"
        echo "Tamaño del archivo: $file_size"
        echo ""
        echo "--- Estadísticas ---"
        echo "Total de errores encontrados: $TOTAL_ERRORS"
        echo ""
        echo "--- Servicios Globales Recolectados ---"
        for f in "${TEMP_DIR}"/global_*.json; do
            [[ -f "$f" ]] || continue
            local svc
            svc=$(basename "$f" .json | sed 's/^global_//')
            local size
            size=$(du -h "$f" | cut -f1)
            echo "  ✓ $svc ($size)"
        done
        echo ""
        echo "--- Regiones Procesadas ---"
        for f in "${TEMP_DIR}"/regions_*.json; do
            [[ -f "$f" ]] || continue
            local reg
            reg=$(basename "$f" .json | sed 's/^regions_//')
            local size
            size=$(du -h "$f" | cut -f1)
            echo "  ✓ $reg ($size)"
        done
        echo ""
        echo "--- Conteo de Recursos Principales ---"
        if [[ -f "$MASTER_FILE" ]]; then
            local instance_count
            instance_count=$(jq '[.regional_services[]?.ec2?.instances?.Reservations[]?.Instances[]?] | length' "$MASTER_FILE" 2>/dev/null || echo "N/A")
            echo "  EC2 Instances: $instance_count"
            
            local vpc_count
            vpc_count=$(jq '[.regional_services[]?.vpc?.vpcs?.Vpcs[]?] | length' "$MASTER_FILE" 2>/dev/null || echo "N/A")
            echo "  VPCs: $vpc_count"
            
            local rds_count
            rds_count=$(jq '[.regional_services[]?.rds?.instances?.DBInstances[]?] | length' "$MASTER_FILE" 2>/dev/null || echo "N/A")
            echo "  RDS Instances: $rds_count"
            
            local lambda_count
            lambda_count=$(jq '[.regional_services[]?.lambda?.functions?.Functions[]?] | length' "$MASTER_FILE" 2>/dev/null || echo "N/A")
            echo "  Lambda Functions: $lambda_count"
            
            local s3_count
            s3_count=$(jq '.global_services?.s3?.buckets?.Buckets? | length' "$MASTER_FILE" 2>/dev/null || echo "N/A")
            echo "  S3 Buckets: $s3_count"
            
            local iam_users
            iam_users=$(jq '.global_services?.iam?.users?.Users? | length' "$MASTER_FILE" 2>/dev/null || echo "N/A")
            echo "  IAM Users: $iam_users"
            
            local iam_roles
            iam_roles=$(jq '.global_services?.iam?.roles?.Roles? | length' "$MASTER_FILE" 2>/dev/null || echo "N/A")
            echo "  IAM Roles: $iam_roles"
        fi
        echo ""
        echo "=============================================="
    } | tee "$SUMMARY_FILE" >&2
}

# =============================================================================
# PUNTO DE ENTRADA PRINCIPAL
# =============================================================================

main() {
    # Parsear argumentos
    parse_args "$@"
    
    # Verificar dependencias
    check_dependencies
    
    # Crear directorios de salida
    mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"
    touch "$ERRORS_LOG"
    
    # Header inicial
    log_section "LEVANTAMIENTO DE INFRAESTRUCTURA AWS"
    log_info "Timestamp: $TIMESTAMP"
    log_info "Directorio de salida: $OUTPUT_DIR"
    
    # Verificar identidad
    log_info "Verificando identidad AWS..."
    local identity
    identity=$(aws ${AWS_PROFILE_ARG} sts get-caller-identity 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        log_error "No se pudo verificar la identidad AWS. Verifique sus credenciales."
        exit 1
    fi
    
    local account_id
    account_id=$(echo "$identity" | jq -r '.Account')
    local caller_arn
    caller_arn=$(echo "$identity" | jq -r '.Arn')
    
    log_ok "Cuenta AWS: $account_id"
    log_ok "Identidad: $caller_arn"
    echo "" >&2
    
    # =========================================================================
    # FASE 1: Servicios Globales
    # =========================================================================
    log_section "FASE 1: SERVICIOS GLOBALES"
    
    discover_iam
    discover_s3
    discover_route53
    discover_cloudfront
    discover_waf_global
    discover_organizations
    discover_cost_explorer
    
    # =========================================================================
    # FASE 2: Servicios Regionales
    # =========================================================================
    log_section "FASE 2: SERVICIOS REGIONALES"
    
    local regions
    regions=$(get_all_regions)
    local region_count
    region_count=$(echo "$regions" | wc -w)
    log_info "Se procesarán $region_count regiones"
    
    local current_region=0
    for region in $regions; do
        ((current_region++))
        log_info "Progreso: Región $current_region de $region_count ($region)"
        discover_region "$region"
    done
    
    # =========================================================================
    # FASE 3: Ensamblaje Final
    # =========================================================================
    assemble_final_json
    
    # =========================================================================
    # FASE 4: Resumen
    # =========================================================================
    generate_summary
    
    # Limpiar archivos temporales
    log_info "Limpiando archivos temporales..."
    rm -rf "$TEMP_DIR"
    
    log_section "LEVANTAMIENTO COMPLETADO"
    log_ok "Archivo principal: $MASTER_FILE"
    log_ok "Resumen: $SUMMARY_FILE"
    log_ok "Log de errores: $ERRORS_LOG"
    
    echo "" >&2
    echo -e "${GREEN}¡Levantamiento finalizado exitosamente!${NC}" >&2
    echo -e "Resultados en: ${CYAN}${OUTPUT_DIR}${NC}" >&2
}

# Ejecutar
main "$@"
