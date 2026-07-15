#!/usr/bin/env bash
# =============================================================================
# levantamiento-do.sh
# Script de descubrimiento exhaustivo de infraestructura DigitalOcean
# 
# Descripción: Recopila TODA la información de infraestructura de una cuenta
#              de DigitalOcean usando únicamente comandos de lectura (read-only).
#              No realiza modificaciones ni genera costos adicionales.
#
# Requisitos:
#   - doctl instalado y autenticado (token con permisos de lectura)
#   - jq instalado para procesamiento JSON
#   - (Opcional) s3cmd configurado para listar Spaces
#
# Uso: ./levantamiento-do.sh [--output-dir /ruta/personalizada]
#
# Autor: Generado para levantamiento de infraestructura
# Fecha: 2026-07-13
# =============================================================================

set -euo pipefail

# =============================================================================
# VARIABLES GLOBALES
# =============================================================================

SCRIPT_VERSION="1.0.0"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_DIR="${1:-$(pwd)}"
OUTPUT_FILE="${OUTPUT_DIR}/digitalocean_inventario_${TIMESTAMP}.json"
TEMP_DIR=$(mktemp -d)
LOG_FILE="${OUTPUT_DIR}/levantamiento_do_${TIMESTAMP}.log"

# Colores para salida en terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # Sin color

# Contadores para resumen final
TOTAL_SERVICIOS=0
SERVICIOS_OK=0
SERVICIOS_ERROR=0
SERVICIOS_VACIOS=0

# =============================================================================
# FUNCIONES UTILITARIAS
# =============================================================================

# Función de logging
log() {
    local nivel="$1"
    shift
    local mensaje="$*"
    local ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[${ts}] [${nivel}] ${mensaje}" >> "${LOG_FILE}"
}

# Mostrar progreso en pantalla (siempre a stderr para no contaminar JSON)
progreso() {
    local icono="$1"
    local mensaje="$2"
    echo -e "${CYAN}${icono}${NC} ${mensaje}" >&2
}

# Mostrar éxito
exito() {
    echo -e "  ${GREEN}✓${NC} $1" >&2
}

# Mostrar advertencia
advertencia() {
    echo -e "  ${YELLOW}⚠${NC} $1" >&2
}

# Mostrar error
error() {
    echo -e "  ${RED}✗${NC} $1" >&2
}

# Ejecutar comando doctl de forma segura
# Captura errores sin detener el script
ejecutar_doctl() {
    local descripcion="$1"
    shift
    local comando="$*"
    
    TOTAL_SERVICIOS=$((TOTAL_SERVICIOS + 1))
    
    # NOTA: eval es inseguro (inyección de comandos) pero necesario aquí para manejar
    # comandos con pipes/redirecciones. Los comandos son hardcodeados en el script,
    # no provienen de input de usuario, por lo que el riesgo es aceptable.
    local resultado
    if resultado=$(eval "${comando}" 2>>"${LOG_FILE}"); then
        if [ -n "${resultado}" ] && [ "${resultado}" != "[]" ] && [ "${resultado}" != "null" ]; then
            SERVICIOS_OK=$((SERVICIOS_OK + 1))
            exito "${descripcion}"
            echo "${resultado}"
            return 0
        else
            SERVICIOS_VACIOS=$((SERVICIOS_VACIOS + 1))
            advertencia "${descripcion} (sin datos)"
            echo "[]"
            return 0
        fi
    else
        SERVICIOS_ERROR=$((SERVICIOS_ERROR + 1))
        error "${descripcion} (error al ejecutar)"
        log "ERROR" "Fallo en: ${comando}"
        echo "null"
        return 0
    fi
}

# Verificar dependencias necesarias
verificar_dependencias() {
    progreso "🔍" "Verificando dependencias..."
    
    if ! command -v doctl &> /dev/null; then
        error "doctl no está instalado. Instálalo desde: https://docs.digitalocean.com/reference/doctl/how-to/install/"
        exit 1
    fi
    exito "doctl encontrado: $(doctl version 2>/dev/null | head -1)"
    
    if ! command -v jq &> /dev/null; then
        error "jq no está instalado. Instálalo con: apt install jq / brew install jq"
        exit 1
    fi
    exito "jq encontrado: $(jq --version)"
    
    # Verificar autenticación
    if ! doctl account get --output json &> /dev/null; then
        error "doctl no está autenticado. Ejecuta: doctl auth init"
        exit 1
    fi
    exito "Autenticación verificada"
    
    # Verificar s3cmd (opcional, para Spaces)
    if command -v s3cmd &> /dev/null; then
        exito "s3cmd encontrado (se usará para Spaces)"
    else
        advertencia "s3cmd no encontrado (Spaces se listará con métodos alternativos)"
    fi
    
    echo "" >&2
}

# Limpieza al salir
limpieza() {
    rm -rf "${TEMP_DIR}" 2>/dev/null || true
}
trap limpieza EXIT


# =============================================================================
# FUNCIONES DE RECOPILACIÓN POR SERVICIO
# =============================================================================

# -----------------------------------------------------------------------------
# CUENTA - Información general de la cuenta
# -----------------------------------------------------------------------------
recopilar_cuenta() {
    progreso "👤" "Recopilando información de cuenta..."
    
    local cuenta
    cuenta=$(ejecutar_doctl "Información de cuenta" "doctl account get --output json")
    
    # Obtener rate limit info
    local rate_limit
    rate_limit=$(ejecutar_doctl "Rate limit" "doctl account ratelimit --output json")
    
    cat <<EOF
{
    "info": ${cuenta},
    "rate_limit": ${rate_limit}
}
EOF
}

# -----------------------------------------------------------------------------
# DROPLETS - Máquinas virtuales
# -----------------------------------------------------------------------------
recopilar_droplets() {
    progreso "💧" "Recopilando Droplets..."
    
    # Listar todos los droplets
    local droplets
    droplets=$(ejecutar_doctl "Lista de droplets" "doctl compute droplet list --output json")
    
    # Para cada droplet, obtener información adicional
    local droplets_detallados="[]"
    
    if [ "${droplets}" != "[]" ] && [ "${droplets}" != "null" ]; then
        local droplet_ids
        droplet_ids=$(echo "${droplets}" | jq -r '.[].id' 2>/dev/null || echo "")
        
        if [ -n "${droplet_ids}" ]; then
            droplets_detallados="["
            local primero=true
            
            for id in ${droplet_ids}; do
                if [ "${primero}" = true ]; then
                    primero=false
                else
                    droplets_detallados+=","
                fi
                
                # Obtener backups del droplet
                local backups
                backups=$(doctl compute droplet backups "${id}" --output json 2>/dev/null || echo "[]")
                
                # Obtener snapshots del droplet
                local snapshots
                snapshots=$(doctl compute droplet snapshots "${id}" --output json 2>/dev/null || echo "[]")
                
                # Obtener firewalls del droplet
                local firewalls
                firewalls=$(doctl compute firewall list-by-droplet "${id}" --output json 2>/dev/null || echo "[]")
                
                # Obtener neighbors (droplets en mismo host físico)
                local neighbors
                neighbors=$(doctl compute droplet neighbors "${id}" --output json 2>/dev/null || echo "[]")
                
                # Construir objeto detallado
                local droplet_base
                droplet_base=$(echo "${droplets}" | jq ".[] | select(.id == ${id})")
                
                droplets_detallados+=$(cat <<INNER
{
    "droplet": ${droplet_base},
    "backups": ${backups},
    "snapshots": ${snapshots},
    "firewalls": ${firewalls},
    "neighbors": ${neighbors}
}
INNER
)
            done
            droplets_detallados+="]"
        fi
    fi
    
    # Listar tamaños disponibles (para referencia)
    local sizes
    sizes=$(ejecutar_doctl "Tamaños disponibles" "doctl compute size list --output json")
    
    # Listar regiones
    local regions
    regions=$(ejecutar_doctl "Regiones disponibles" "doctl compute region list --output json")
    
    # Listar imágenes propias
    local images_privadas
    images_privadas=$(ejecutar_doctl "Imágenes privadas" "doctl compute image list-user --output json")
    
    # Listar imágenes de distribución
    local images_distro
    images_distro=$(ejecutar_doctl "Imágenes de distribución" "doctl compute image list-distribution --output json")
    
    # Listar imágenes de aplicación
    local images_app
    images_app=$(ejecutar_doctl "Imágenes de aplicación" "doctl compute image list-application --output json")
    
    cat <<EOF
{
    "droplets_detallados": ${droplets_detallados},
    "total_droplets": $(echo "${droplets}" | jq 'length' 2>/dev/null || echo 0),
    "sizes_disponibles": ${sizes},
    "regiones": ${regions},
    "imagenes_privadas": ${images_privadas},
    "imagenes_distribucion": ${images_distro},
    "imagenes_aplicacion": ${images_app}
}
EOF
}

# -----------------------------------------------------------------------------
# KUBERNETES (DOKS) - Clusters Kubernetes gestionados
# -----------------------------------------------------------------------------
recopilar_kubernetes() {
    progreso "☸️" "Recopilando Kubernetes (DOKS)..."
    
    local clusters
    clusters=$(ejecutar_doctl "Clusters K8s" "doctl kubernetes cluster list --output json")
    
    local clusters_detallados="[]"
    
    if [ "${clusters}" != "[]" ] && [ "${clusters}" != "null" ]; then
        local cluster_ids
        cluster_ids=$(echo "${clusters}" | jq -r '.[].id' 2>/dev/null || echo "")
        
        if [ -n "${cluster_ids}" ]; then
            clusters_detallados="["
            local primero=true
            
            for id in ${cluster_ids}; do
                if [ "${primero}" = true ]; then
                    primero=false
                else
                    clusters_detallados+=","
                fi
                
                # Node pools del cluster
                local node_pools
                node_pools=$(doctl kubernetes cluster node-pool list "${id}" --output json 2>/dev/null || echo "[]")
                
                # Opciones disponibles del cluster
                local cluster_base
                cluster_base=$(echo "${clusters}" | jq ".[] | select(.id == \"${id}\")")
                
                clusters_detallados+=$(cat <<INNER
{
    "cluster": ${cluster_base},
    "node_pools": ${node_pools}
}
INNER
)
            done
            clusters_detallados+="]"
        fi
    fi
    
    # Opciones disponibles de K8s
    local opciones
    opciones=$(ejecutar_doctl "Opciones K8s" "doctl kubernetes options --output json")
    
    cat <<EOF
{
    "clusters_detallados": ${clusters_detallados},
    "total_clusters": $(echo "${clusters}" | jq 'length' 2>/dev/null || echo 0),
    "opciones_disponibles": ${opciones}
}
EOF
}


# -----------------------------------------------------------------------------
# APP PLATFORM - Aplicaciones PaaS
# -----------------------------------------------------------------------------
recopilar_app_platform() {
    progreso "🚀" "Recopilando App Platform..."
    
    local apps
    apps=$(ejecutar_doctl "Aplicaciones" "doctl apps list --output json")
    
    local apps_detalladas="[]"
    
    if [ "${apps}" != "[]" ] && [ "${apps}" != "null" ]; then
        local app_ids
        app_ids=$(echo "${apps}" | jq -r '.[].id' 2>/dev/null || echo "")
        
        if [ -n "${app_ids}" ]; then
            apps_detalladas="["
            local primero=true
            
            for id in ${app_ids}; do
                if [ "${primero}" = true ]; then
                    primero=false
                else
                    apps_detalladas+=","
                fi
                
                # Obtener detalle completo de la app
                local app_detalle
                app_detalle=$(doctl apps get "${id}" --output json 2>/dev/null || echo "{}")
                
                # Obtener deployments recientes
                local deployments
                deployments=$(doctl apps list-deployments "${id}" --output json 2>/dev/null || echo "[]")
                
                # Obtener alertas de la app
                local alertas
                alertas=$(doctl apps list-alerts "${id}" --output json 2>/dev/null || echo "[]")
                
                apps_detalladas+=$(cat <<INNER
{
    "app": ${app_detalle},
    "deployments": ${deployments},
    "alertas": ${alertas}
}
INNER
)
            done
            apps_detalladas+="]"
        fi
    fi
    
    # Listar tiers/regiones disponibles
    local tiers
    tiers=$(ejecutar_doctl "App tiers" "doctl apps tier list --output json")
    
    local regiones
    regiones=$(ejecutar_doctl "App regiones" "doctl apps region list --output json")
    
    cat <<EOF
{
    "apps_detalladas": ${apps_detalladas},
    "total_apps": $(echo "${apps}" | jq 'length' 2>/dev/null || echo 0),
    "tiers_disponibles": ${tiers},
    "regiones_disponibles": ${regiones}
}
EOF
}

# -----------------------------------------------------------------------------
# FUNCTIONS - Serverless Functions
# -----------------------------------------------------------------------------
recopilar_functions() {
    progreso "⚡" "Recopilando Functions (Serverless)..."
    
    # Listar namespaces de funciones
    local namespaces
    namespaces=$(ejecutar_doctl "Namespaces" "doctl serverless namespaces list --output json")
    
    local namespaces_detallados="[]"
    
    if [ "${namespaces}" != "[]" ] && [ "${namespaces}" != "null" ]; then
        # Si hay namespaces conectados, obtener funciones
        local funciones
        funciones=$(doctl serverless functions list --output json 2>/dev/null || echo "[]")
        
        local triggers
        triggers=$(doctl serverless triggers list --output json 2>/dev/null || echo "[]")
        
        namespaces_detallados=$(cat <<INNER
{
    "namespaces": ${namespaces},
    "functions": ${funciones},
    "triggers": ${triggers}
}
INNER
)
    fi
    
    cat <<EOF
{
    "serverless": ${namespaces_detallados},
    "total_namespaces": $(echo "${namespaces}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}

# -----------------------------------------------------------------------------
# DATABASES - Bases de datos gestionadas
# -----------------------------------------------------------------------------
recopilar_databases() {
    progreso "🗄️" "Recopilando Databases..."
    
    local clusters
    clusters=$(ejecutar_doctl "Clusters de BD" "doctl databases list --output json")
    
    local clusters_detallados="[]"
    
    if [ "${clusters}" != "[]" ] && [ "${clusters}" != "null" ]; then
        local cluster_ids
        cluster_ids=$(echo "${clusters}" | jq -r '.[].id' 2>/dev/null || echo "")
        
        if [ -n "${cluster_ids}" ]; then
            clusters_detallados="["
            local primero=true
            
            for id in ${cluster_ids}; do
                if [ "${primero}" = true ]; then
                    primero=false
                else
                    clusters_detallados+=","
                fi
                
                # Obtener detalle del cluster
                local cluster_base
                cluster_base=$(echo "${clusters}" | jq ".[] | select(.id == \"${id}\")")
                
                # Bases de datos dentro del cluster
                local dbs
                dbs=$(doctl databases db list "${id}" --output json 2>/dev/null || echo "[]")
                
                # Usuarios del cluster
                local usuarios
                usuarios=$(doctl databases user list "${id}" --output json 2>/dev/null || echo "[]")
                
                # Connection pools (solo PostgreSQL)
                local pools
                pools=$(doctl databases pool list "${id}" --output json 2>/dev/null || echo "[]")
                
                # Réplicas de lectura
                local replicas
                replicas=$(doctl databases replica list "${id}" --output json 2>/dev/null || echo "[]")
                
                # Reglas de firewall de la BD
                local fw_rules
                fw_rules=$(doctl databases firewalls list "${id}" --output json 2>/dev/null || echo "[]")
                
                # Backups disponibles
                local backups
                backups=$(doctl databases backups list "${id}" --output json 2>/dev/null || echo "[]")
                
                # Opciones de mantenimiento
                local mantenimiento
                mantenimiento=$(doctl databases maintenance-window get "${id}" --output json 2>/dev/null || echo "{}")
                
                # SQL modes (solo MySQL)
                local sql_modes
                sql_modes=$(doctl databases sql-mode get "${id}" --output json 2>/dev/null || echo "null")
                
                # Tópicos (solo Kafka)
                local topics
                topics=$(doctl databases topics list "${id}" --output json 2>/dev/null || echo "null")
                
                clusters_detallados+=$(cat <<INNER
{
    "cluster": ${cluster_base},
    "databases": ${dbs},
    "usuarios": ${usuarios},
    "connection_pools": ${pools},
    "replicas": ${replicas},
    "firewall_rules": ${fw_rules},
    "backups": ${backups},
    "mantenimiento": ${mantenimiento},
    "sql_modes": ${sql_modes},
    "topics_kafka": ${topics}
}
INNER
)
            done
            clusters_detallados+="]"
        fi
    fi
    
    # Opciones disponibles de bases de datos
    local opciones
    opciones=$(ejecutar_doctl "Opciones de BD" "doctl databases options --output json")
    
    # Motores disponibles
    local engines
    engines=$(ejecutar_doctl "Motores de BD" "doctl databases engine list --output json")
    
    cat <<EOF
{
    "clusters_detallados": ${clusters_detallados},
    "total_clusters": $(echo "${clusters}" | jq 'length' 2>/dev/null || echo 0),
    "opciones_disponibles": ${opciones},
    "engines_disponibles": ${engines}
}
EOF
}


# -----------------------------------------------------------------------------
# SPACES - Object Storage (compatible S3)
# -----------------------------------------------------------------------------
recopilar_spaces() {
    progreso "📦" "Recopilando Spaces (Object Storage)..."
    
    local spaces_resultado="[]"
    
    # Intentar con s3cmd primero (más completo para Spaces)
    if command -v s3cmd &> /dev/null; then
        local buckets_raw
        buckets_raw=$(s3cmd ls 2>/dev/null || echo "")
        
        if [ -n "${buckets_raw}" ]; then
            # Convertir salida de s3cmd a JSON
            spaces_resultado="["
            local primero=true
            
            while IFS= read -r linea; do
                if [ -n "${linea}" ]; then
                    local fecha=$(echo "${linea}" | awk '{print $1" "$2}')
                    local bucket=$(echo "${linea}" | awk '{print $3}' | sed 's|s3://||' | sed 's|/||')
                    
                    if [ "${primero}" = true ]; then
                        primero=false
                    else
                        spaces_resultado+=","
                    fi
                    
                    # Obtener info del bucket
                    local bucket_info
                    bucket_info=$(s3cmd info "s3://${bucket}" 2>/dev/null || echo "")
                    
                    local location=$(echo "${bucket_info}" | grep "Location" | awk '{print $NF}' || echo "unknown")
                    
                    spaces_resultado+="{\"name\": \"${bucket}\", \"created\": \"${fecha}\", \"location\": \"${location}\"}"
                fi
            done <<< "${buckets_raw}"
            
            spaces_resultado+="]"
            exito "Spaces listados via s3cmd"
        else
            advertencia "No se encontraron Spaces o s3cmd no está configurado"
        fi
    else
        advertencia "s3cmd no disponible - Spaces no pueden listarse completamente con doctl"
        # doctl no tiene soporte nativo completo para Spaces
        # Se intenta con la API directamente si está disponible
    fi
    
    cat <<EOF
{
    "spaces": ${spaces_resultado},
    "nota": "Para listado completo de Spaces usar s3cmd o API directa"
}
EOF
}

# -----------------------------------------------------------------------------
# VOLUMES - Block Storage
# -----------------------------------------------------------------------------
recopilar_volumes() {
    progreso "💾" "Recopilando Volumes (Block Storage)..."
    
    # Listar todos los volúmenes
    local volumes
    volumes=$(ejecutar_doctl "Volúmenes" "doctl compute volume list --output json")
    
    # Listar snapshots de volúmenes
    local vol_snapshots
    vol_snapshots=$(ejecutar_doctl "Snapshots de volúmenes" "doctl compute snapshot list --resource volume --output json")
    
    cat <<EOF
{
    "volumes": ${volumes},
    "total_volumes": $(echo "${volumes}" | jq 'length' 2>/dev/null || echo 0),
    "snapshots_volumenes": ${vol_snapshots}
}
EOF
}

# -----------------------------------------------------------------------------
# VPCs - Redes Privadas Virtuales
# -----------------------------------------------------------------------------
recopilar_vpcs() {
    progreso "🌐" "Recopilando VPCs..."
    
    local vpcs
    vpcs=$(ejecutar_doctl "VPCs" "doctl vpcs list --output json")
    
    local vpcs_detalladas="[]"
    
    if [ "${vpcs}" != "[]" ] && [ "${vpcs}" != "null" ]; then
        local vpc_ids
        vpc_ids=$(echo "${vpcs}" | jq -r '.[].id' 2>/dev/null || echo "")
        
        if [ -n "${vpc_ids}" ]; then
            vpcs_detalladas="["
            local primero=true
            
            for id in ${vpc_ids}; do
                if [ "${primero}" = true ]; then
                    primero=false
                else
                    vpcs_detalladas+=","
                fi
                
                # Obtener miembros de la VPC
                local miembros
                miembros=$(doctl vpcs members list "${id}" --output json 2>/dev/null || echo "[]")
                
                local vpc_base
                vpc_base=$(echo "${vpcs}" | jq ".[] | select(.id == \"${id}\")")
                
                vpcs_detalladas+=$(cat <<INNER
{
    "vpc": ${vpc_base},
    "miembros": ${miembros},
    "total_miembros": $(echo "${miembros}" | jq 'length' 2>/dev/null || echo 0)
}
INNER
)
            done
            vpcs_detalladas+="]"
        fi
    fi
    
    cat <<EOF
{
    "vpcs_detalladas": ${vpcs_detalladas},
    "total_vpcs": $(echo "${vpcs}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}

# -----------------------------------------------------------------------------
# LOAD BALANCERS - Balanceadores de carga
# -----------------------------------------------------------------------------
recopilar_load_balancers() {
    progreso "⚖️" "Recopilando Load Balancers..."
    
    local lbs
    lbs=$(ejecutar_doctl "Load Balancers" "doctl compute load-balancer list --output json")
    
    # Los LBs ya incluyen forwarding rules, health checks y droplet IDs en su JSON
    cat <<EOF
{
    "load_balancers": ${lbs},
    "total_load_balancers": $(echo "${lbs}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}


# -----------------------------------------------------------------------------
# FIREWALLS - Reglas de firewall
# -----------------------------------------------------------------------------
recopilar_firewalls() {
    progreso "🛡️" "Recopilando Firewalls..."
    
    local firewalls
    firewalls=$(ejecutar_doctl "Firewalls" "doctl compute firewall list --output json")
    
    # Los firewalls ya incluyen inbound/outbound rules y droplet_ids en su JSON
    cat <<EOF
{
    "firewalls": ${firewalls},
    "total_firewalls": $(echo "${firewalls}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}

# -----------------------------------------------------------------------------
# FLOATING IPs - IPs flotantes (legacy, reemplazado por Reserved IPs)
# -----------------------------------------------------------------------------
recopilar_floating_ips() {
    progreso "🔗" "Recopilando Floating IPs..."
    
    local floating_ips
    floating_ips=$(ejecutar_doctl "Floating IPs" "doctl compute floating-ip list --output json")
    
    cat <<EOF
{
    "floating_ips": ${floating_ips},
    "total_floating_ips": $(echo "${floating_ips}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}

# -----------------------------------------------------------------------------
# RESERVED IPs - IPs reservadas
# -----------------------------------------------------------------------------
recopilar_reserved_ips() {
    progreso "📌" "Recopilando Reserved IPs..."
    
    local reserved_ips
    reserved_ips=$(ejecutar_doctl "Reserved IPs" "doctl compute reserved-ip list --output json")
    
    cat <<EOF
{
    "reserved_ips": ${reserved_ips},
    "total_reserved_ips": $(echo "${reserved_ips}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}

# -----------------------------------------------------------------------------
# DOMAINS y DNS - Dominios y registros DNS
# -----------------------------------------------------------------------------
recopilar_domains() {
    progreso "🌍" "Recopilando Domains y DNS..."
    
    local dominios
    dominios=$(ejecutar_doctl "Dominios" "doctl compute domain list --output json")
    
    local dominios_detallados="[]"
    
    if [ "${dominios}" != "[]" ] && [ "${dominios}" != "null" ]; then
        local domain_names
        domain_names=$(echo "${dominios}" | jq -r '.[].name' 2>/dev/null || echo "")
        
        if [ -n "${domain_names}" ]; then
            dominios_detallados="["
            local primero=true
            
            for nombre in ${domain_names}; do
                if [ "${primero}" = true ]; then
                    primero=false
                else
                    dominios_detallados+=","
                fi
                
                # Obtener registros DNS del dominio
                local registros
                registros=$(doctl compute domain records list "${nombre}" --output json 2>/dev/null || echo "[]")
                
                dominios_detallados+=$(cat <<INNER
{
    "domain": "${nombre}",
    "records": ${registros},
    "total_records": $(echo "${registros}" | jq 'length' 2>/dev/null || echo 0)
}
INNER
)
            done
            dominios_detallados+="]"
        fi
    fi
    
    cat <<EOF
{
    "dominios_detallados": ${dominios_detallados},
    "total_dominios": $(echo "${dominios}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}

# -----------------------------------------------------------------------------
# CDN - Content Delivery Network endpoints
# -----------------------------------------------------------------------------
recopilar_cdn() {
    progreso "🌐" "Recopilando CDN Endpoints..."
    
    local cdn_endpoints
    cdn_endpoints=$(ejecutar_doctl "CDN Endpoints" "doctl compute cdn list --output json")
    
    cat <<EOF
{
    "cdn_endpoints": ${cdn_endpoints},
    "total_cdn": $(echo "${cdn_endpoints}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}


# -----------------------------------------------------------------------------
# CONTAINER REGISTRY - Registro de contenedores
# -----------------------------------------------------------------------------
recopilar_registry() {
    progreso "🐳" "Recopilando Container Registry..."
    
    # Obtener info del registry
    local registry
    registry=$(ejecutar_doctl "Container Registry" "doctl registry get --output json")
    
    local repos="[]"
    local gc_info="null"
    
    if [ "${registry}" != "null" ] && [ "${registry}" != "[]" ]; then
        # Listar repositorios
        repos=$(ejecutar_doctl "Repositorios" "doctl registry repository list-v2 --output json")
        
        # Info de garbage collection
        gc_info=$(ejecutar_doctl "Garbage Collection" "doctl registry garbage-collection get-active --output json")
        
        # Historial de GC
        local gc_history
        gc_history=$(ejecutar_doctl "Historial GC" "doctl registry garbage-collection list --output json")
        
        # Obtener tags por repositorio
        local repos_con_tags="[]"
        if [ "${repos}" != "[]" ] && [ "${repos}" != "null" ]; then
            local repo_names
            repo_names=$(echo "${repos}" | jq -r '.[].name' 2>/dev/null || echo "")
            
            if [ -n "${repo_names}" ]; then
                repos_con_tags="["
                local primero=true
                local reg_name
                reg_name=$(echo "${registry}" | jq -r '.name // .registry_name // empty' 2>/dev/null || echo "")
                
                for repo in ${repo_names}; do
                    if [ "${primero}" = true ]; then
                        primero=false
                    else
                        repos_con_tags+=","
                    fi
                    
                    local tags
                    tags=$(doctl registry repository list-tags "${repo}" --output json 2>/dev/null || echo "[]")
                    
                    repos_con_tags+="{\"repository\": \"${repo}\", \"tags\": ${tags}}"
                done
                repos_con_tags+="]"
            fi
        fi
        
        cat <<EOF
{
    "registry": ${registry},
    "repositorios": ${repos_con_tags},
    "garbage_collection_activa": ${gc_info},
    "garbage_collection_historial": ${gc_history}
}
EOF
    else
        cat <<EOF
{
    "registry": null,
    "nota": "No hay Container Registry configurado"
}
EOF
    fi
}

# -----------------------------------------------------------------------------
# MONITORING - Alertas y monitoreo
# -----------------------------------------------------------------------------
recopilar_monitoring() {
    progreso "📊" "Recopilando Monitoring..."
    
    # Políticas de alertas
    local alertas
    alertas=$(ejecutar_doctl "Políticas de alerta" "doctl monitoring alert list-policies --output json")
    
    cat <<EOF
{
    "alert_policies": ${alertas},
    "total_alertas": $(echo "${alertas}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}

# -----------------------------------------------------------------------------
# SSH KEYS - Llaves SSH registradas
# -----------------------------------------------------------------------------
recopilar_ssh_keys() {
    progreso "🔑" "Recopilando SSH Keys..."
    
    local keys
    keys=$(ejecutar_doctl "SSH Keys" "doctl compute ssh-key list --output json")
    
    cat <<EOF
{
    "ssh_keys": ${keys},
    "total_keys": $(echo "${keys}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}

# -----------------------------------------------------------------------------
# SNAPSHOTS - Snapshots de droplets y volúmenes
# -----------------------------------------------------------------------------
recopilar_snapshots() {
    progreso "📸" "Recopilando Snapshots..."
    
    # Snapshots de droplets
    local snap_droplets
    snap_droplets=$(ejecutar_doctl "Snapshots de droplets" "doctl compute snapshot list --resource droplet --output json")
    
    # Snapshots de volúmenes
    local snap_volumes
    snap_volumes=$(ejecutar_doctl "Snapshots de volúmenes" "doctl compute snapshot list --resource volume --output json")
    
    cat <<EOF
{
    "snapshots_droplets": ${snap_droplets},
    "snapshots_volumes": ${snap_volumes},
    "total_snapshots_droplets": $(echo "${snap_droplets}" | jq 'length' 2>/dev/null || echo 0),
    "total_snapshots_volumes": $(echo "${snap_volumes}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}


# -----------------------------------------------------------------------------
# PROJECTS - Proyectos y recursos asociados
# -----------------------------------------------------------------------------
recopilar_projects() {
    progreso "📁" "Recopilando Projects..."
    
    local proyectos
    proyectos=$(ejecutar_doctl "Proyectos" "doctl projects list --output json")
    
    local proyectos_detallados="[]"
    
    if [ "${proyectos}" != "[]" ] && [ "${proyectos}" != "null" ]; then
        local project_ids
        project_ids=$(echo "${proyectos}" | jq -r '.[].id' 2>/dev/null || echo "")
        
        if [ -n "${project_ids}" ]; then
            proyectos_detallados="["
            local primero=true
            
            for id in ${project_ids}; do
                if [ "${primero}" = true ]; then
                    primero=false
                else
                    proyectos_detallados+=","
                fi
                
                # Recursos del proyecto
                local recursos
                recursos=$(doctl projects resources list "${id}" --output json 2>/dev/null || echo "[]")
                
                local proyecto_base
                proyecto_base=$(echo "${proyectos}" | jq ".[] | select(.id == \"${id}\")")
                
                proyectos_detallados+=$(cat <<INNER
{
    "proyecto": ${proyecto_base},
    "recursos": ${recursos},
    "total_recursos": $(echo "${recursos}" | jq 'length' 2>/dev/null || echo 0)
}
INNER
)
            done
            proyectos_detallados+="]"
        fi
    fi
    
    cat <<EOF
{
    "proyectos_detallados": ${proyectos_detallados},
    "total_proyectos": $(echo "${proyectos}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}

# -----------------------------------------------------------------------------
# BILLING - Facturación y balance
# -----------------------------------------------------------------------------
recopilar_billing() {
    progreso "💰" "Recopilando Billing..."
    
    # Balance actual
    local balance
    balance=$(ejecutar_doctl "Balance" "doctl balance get --output json")
    
    # Historial de facturación
    local historial
    historial=$(ejecutar_doctl "Historial de facturación" "doctl billing-history list --output json")
    
    cat <<EOF
{
    "balance": ${balance},
    "historial_facturacion": ${historial}
}
EOF
}

# -----------------------------------------------------------------------------
# INVOICES - Facturas
# -----------------------------------------------------------------------------
recopilar_invoices() {
    progreso "🧾" "Recopilando Invoices..."
    
    # Listar facturas recientes
    local facturas
    facturas=$(ejecutar_doctl "Facturas" "doctl invoice list --output json")
    
    # Obtener detalle de las últimas facturas (máximo 3)
    local facturas_detalladas="[]"
    
    if [ "${facturas}" != "[]" ] && [ "${facturas}" != "null" ]; then
        local invoice_ids
        invoice_ids=$(echo "${facturas}" | jq -r '.[0:3][].invoice_uuid // .[0:3][].id' 2>/dev/null || echo "")
        
        if [ -n "${invoice_ids}" ]; then
            facturas_detalladas="["
            local primero=true
            
            for id in ${invoice_ids}; do
                if [ "${primero}" = true ]; then
                    primero=false
                else
                    facturas_detalladas+=","
                fi
                
                local detalle
                detalle=$(doctl invoice get "${id}" --output json 2>/dev/null || echo "{}")
                
                local summary
                summary=$(doctl invoice summary "${id}" --output json 2>/dev/null || echo "{}")
                
                facturas_detalladas+="{\"invoice_id\": \"${id}\", \"detalle\": ${detalle}, \"resumen\": ${summary}}"
            done
            facturas_detalladas+="]"
        fi
    fi
    
    cat <<EOF
{
    "facturas_lista": ${facturas},
    "facturas_detalladas": ${facturas_detalladas},
    "total_facturas": $(echo "${facturas}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}

# -----------------------------------------------------------------------------
# ACTIONS - Acciones recientes de la cuenta
# -----------------------------------------------------------------------------
recopilar_actions() {
    progreso "📋" "Recopilando Actions recientes..."
    
    # Últimas acciones (limitado para no sobrecargar)
    local acciones
    acciones=$(ejecutar_doctl "Acciones recientes" "doctl compute action list --output json")
    
    cat <<EOF
{
    "acciones_recientes": ${acciones},
    "total_acciones": $(echo "${acciones}" | jq 'length' 2>/dev/null || echo 0),
    "nota": "Se muestran las acciones más recientes de la cuenta"
}
EOF
}

# -----------------------------------------------------------------------------
# TAGS - Etiquetas y recursos asociados
# -----------------------------------------------------------------------------
recopilar_tags() {
    progreso "🏷️" "Recopilando Tags..."
    
    local tags
    tags=$(ejecutar_doctl "Tags" "doctl compute tag list --output json")
    
    # Los tags ya incluyen conteo de recursos por tipo en su respuesta JSON
    cat <<EOF
{
    "tags": ${tags},
    "total_tags": $(echo "${tags}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}

# -----------------------------------------------------------------------------
# UPTIME - Checks y alertas de uptime
# -----------------------------------------------------------------------------
recopilar_uptime() {
    progreso "⏱️" "Recopilando Uptime Checks..."
    
    local checks
    checks=$(ejecutar_doctl "Uptime checks" "doctl monitoring uptime check list --output json")
    
    local checks_detallados="[]"
    
    if [ "${checks}" != "[]" ] && [ "${checks}" != "null" ]; then
        local check_ids
        check_ids=$(echo "${checks}" | jq -r '.[].id' 2>/dev/null || echo "")
        
        if [ -n "${check_ids}" ]; then
            checks_detallados="["
            local primero=true
            
            for id in ${check_ids}; do
                if [ "${primero}" = true ]; then
                    primero=false
                else
                    checks_detallados+=","
                fi
                
                # Alertas del check
                local alertas
                alertas=$(doctl monitoring uptime alert list "${id}" --output json 2>/dev/null || echo "[]")
                
                local check_base
                check_base=$(echo "${checks}" | jq ".[] | select(.id == \"${id}\")")
                
                checks_detallados+=$(cat <<INNER
{
    "check": ${check_base},
    "alertas": ${alertas}
}
INNER
)
            done
            checks_detallados+="]"
        fi
    fi
    
    cat <<EOF
{
    "uptime_checks_detallados": ${checks_detallados},
    "total_checks": $(echo "${checks}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}


# -----------------------------------------------------------------------------
# CERTIFICATES - Certificados SSL/TLS
# -----------------------------------------------------------------------------
recopilar_certificates() {
    progreso "🔒" "Recopilando Certificates..."
    
    local certificates
    certificates=$(ejecutar_doctl "Certificados SSL/TLS" "doctl compute certificate list --output json")
    
    cat <<EOF
{
    "certificates": ${certificates},
    "total_certificates": $(echo "${certificates}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}

# -----------------------------------------------------------------------------
# VPC PEERING - Peerings entre VPCs
# -----------------------------------------------------------------------------
recopilar_vpc_peering() {
    progreso "🔗" "Recopilando VPC Peerings..."
    
    # Este comando puede no existir en versiones antiguas de doctl
    local peerings
    peerings=$(ejecutar_doctl "VPC Peerings" "doctl vpcs peerings list --output json")
    
    cat <<EOF
{
    "vpc_peerings": ${peerings},
    "total_peerings": $(echo "${peerings}" | jq 'length' 2>/dev/null || echo 0)
}
EOF
}


# =============================================================================
# FUNCIÓN PRINCIPAL - Orquestación
# =============================================================================
main() {
    clear
    echo "" >&2
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${BLUE}║     🌊 LEVANTAMIENTO DE INFRAESTRUCTURA DIGITALOCEAN 🌊        ║${NC}" >&2
    echo -e "${BLUE}║                    Versión ${SCRIPT_VERSION}                              ║${NC}" >&2
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}" >&2
    echo "" >&2
    echo -e "  📅 Fecha: $(date '+%Y-%m-%d %H:%M:%S %Z')" >&2
    echo -e "  📂 Salida: ${OUTPUT_FILE}" >&2
    echo -e "  📝 Log: ${LOG_FILE}" >&2
    echo "" >&2
    echo -e "${YELLOW}────────────────────────────────────────────────────────────────────${NC}" >&2
    echo "" >&2
    
    # Iniciar log
    log "INFO" "Inicio de levantamiento DigitalOcean v${SCRIPT_VERSION}"
    log "INFO" "Archivo de salida: ${OUTPUT_FILE}"
    
    # Verificar dependencias
    verificar_dependencias
    
    echo -e "${YELLOW}────────────────────────────────────────────────────────────────────${NC}" >&2
    echo -e "${GREEN} Iniciando recopilación de servicios...${NC}" >&2
    echo -e "${YELLOW}────────────────────────────────────────────────────────────────────${NC}" >&2
    echo "" >&2
    
    local INICIO=$(date +%s)
    
    # --- Recopilar cada servicio y guardar en archivos temporales ---
    
    recopilar_cuenta > "${TEMP_DIR}/01_cuenta.json"
    recopilar_droplets > "${TEMP_DIR}/02_droplets.json"
    recopilar_kubernetes > "${TEMP_DIR}/03_kubernetes.json"
    recopilar_app_platform > "${TEMP_DIR}/04_app_platform.json"
    recopilar_functions > "${TEMP_DIR}/05_functions.json"
    recopilar_databases > "${TEMP_DIR}/06_databases.json"
    recopilar_spaces > "${TEMP_DIR}/07_spaces.json"
    recopilar_volumes > "${TEMP_DIR}/08_volumes.json"
    recopilar_vpcs > "${TEMP_DIR}/09_vpcs.json"
    recopilar_load_balancers > "${TEMP_DIR}/10_load_balancers.json"
    recopilar_firewalls > "${TEMP_DIR}/11_firewalls.json"
    recopilar_floating_ips > "${TEMP_DIR}/12_floating_ips.json"
    recopilar_reserved_ips > "${TEMP_DIR}/13_reserved_ips.json"
    recopilar_domains > "${TEMP_DIR}/14_domains.json"
    recopilar_cdn > "${TEMP_DIR}/15_cdn.json"
    recopilar_registry > "${TEMP_DIR}/16_registry.json"
    recopilar_monitoring > "${TEMP_DIR}/17_monitoring.json"
    recopilar_ssh_keys > "${TEMP_DIR}/18_ssh_keys.json"
    recopilar_snapshots > "${TEMP_DIR}/19_snapshots.json"
    recopilar_projects > "${TEMP_DIR}/20_projects.json"
    recopilar_billing > "${TEMP_DIR}/21_billing.json"
    recopilar_invoices > "${TEMP_DIR}/22_invoices.json"
    recopilar_actions > "${TEMP_DIR}/23_actions.json"
    recopilar_tags > "${TEMP_DIR}/24_tags.json"
    recopilar_uptime > "${TEMP_DIR}/25_uptime.json"
    recopilar_certificates > "${TEMP_DIR}/26_certificates.json"
    recopilar_vpc_peering > "${TEMP_DIR}/27_vpc_peering.json"
    
    local FIN=$(date +%s)
    local DURACION=$((FIN - INICIO))
    
    echo "" >&2
    echo -e "${YELLOW}────────────────────────────────────────────────────────────────────${NC}" >&2
    progreso "📄" "Generando archivo JSON consolidado..."
    echo -e "${YELLOW}────────────────────────────────────────────────────────────────────${NC}" >&2
    
    # --- Ensamblar el JSON maestro ---
    cat <<EOF > "${OUTPUT_FILE}"
{
    "_metadata": {
        "herramienta": "levantamiento-do.sh",
        "version": "${SCRIPT_VERSION}",
        "fecha_ejecucion": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
        "fecha_local": "$(date '+%Y-%m-%d %H:%M:%S %Z')",
        "duracion_segundos": ${DURACION},
        "doctl_version": "$(doctl version 2>/dev/null | head -1)",
        "servicios_consultados": ${TOTAL_SERVICIOS},
        "servicios_exitosos": ${SERVICIOS_OK},
        "servicios_con_error": ${SERVICIOS_ERROR},
        "servicios_sin_datos": ${SERVICIOS_VACIOS}
    },
    "cuenta": $(cat "${TEMP_DIR}/01_cuenta.json"),
    "droplets": $(cat "${TEMP_DIR}/02_droplets.json"),
    "kubernetes": $(cat "${TEMP_DIR}/03_kubernetes.json"),
    "app_platform": $(cat "${TEMP_DIR}/04_app_platform.json"),
    "functions": $(cat "${TEMP_DIR}/05_functions.json"),
    "databases": $(cat "${TEMP_DIR}/06_databases.json"),
    "spaces": $(cat "${TEMP_DIR}/07_spaces.json"),
    "volumes": $(cat "${TEMP_DIR}/08_volumes.json"),
    "vpcs": $(cat "${TEMP_DIR}/09_vpcs.json"),
    "load_balancers": $(cat "${TEMP_DIR}/10_load_balancers.json"),
    "firewalls": $(cat "${TEMP_DIR}/11_firewalls.json"),
    "floating_ips": $(cat "${TEMP_DIR}/12_floating_ips.json"),
    "reserved_ips": $(cat "${TEMP_DIR}/13_reserved_ips.json"),
    "domains": $(cat "${TEMP_DIR}/14_domains.json"),
    "cdn": $(cat "${TEMP_DIR}/15_cdn.json"),
    "container_registry": $(cat "${TEMP_DIR}/16_registry.json"),
    "monitoring": $(cat "${TEMP_DIR}/17_monitoring.json"),
    "ssh_keys": $(cat "${TEMP_DIR}/18_ssh_keys.json"),
    "snapshots": $(cat "${TEMP_DIR}/19_snapshots.json"),
    "projects": $(cat "${TEMP_DIR}/20_projects.json"),
    "billing": $(cat "${TEMP_DIR}/21_billing.json"),
    "invoices": $(cat "${TEMP_DIR}/22_invoices.json"),
    "actions": $(cat "${TEMP_DIR}/23_actions.json"),
    "tags": $(cat "${TEMP_DIR}/24_tags.json"),
    "uptime": $(cat "${TEMP_DIR}/25_uptime.json"),
    "certificates": $(cat "${TEMP_DIR}/26_certificates.json"),
    "vpc_peering": $(cat "${TEMP_DIR}/27_vpc_peering.json")
}
EOF

    # Validar JSON resultante
    if jq '.' "${OUTPUT_FILE}" > /dev/null 2>&1; then
        # Formatear el JSON correctamente
        local temp_formatted="${TEMP_DIR}/formatted.json"
        jq '.' "${OUTPUT_FILE}" > "${temp_formatted}" && mv "${temp_formatted}" "${OUTPUT_FILE}"
        exito "JSON válido generado correctamente"
    else
        advertencia "El JSON puede tener errores de formato. Intentando reparar..."
        # Intentar reparar con jq en modo permisivo
        if python3 -c "import json; f=open('${OUTPUT_FILE}'); json.load(f)" 2>/dev/null; then
            exito "JSON validado con Python"
        else
            error "El JSON tiene errores. Revisar manualmente."
        fi
    fi
    
    # --- Resumen final ---
    local TAMANO=$(du -sh "${OUTPUT_FILE}" | cut -f1)
    
    echo "" >&2
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${BLUE}║                    📊 RESUMEN DE EJECUCIÓN                      ║${NC}" >&2
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}" >&2
    echo "" >&2
    echo -e "  ⏱️  Duración total:          ${DURACION} segundos" >&2
    echo -e "  📊 Servicios consultados:   ${TOTAL_SERVICIOS}" >&2
    echo -e "  ${GREEN}✓${NC}  Exitosos:               ${SERVICIOS_OK}" >&2
    echo -e "  ${YELLOW}⚠${NC}  Sin datos:               ${SERVICIOS_VACIOS}" >&2
    echo -e "  ${RED}✗${NC}  Con error:               ${SERVICIOS_ERROR}" >&2
    echo -e "  💾 Tamaño del archivo:      ${TAMANO}" >&2
    echo "" >&2
    echo -e "  📄 Archivo JSON: ${GREEN}${OUTPUT_FILE}${NC}" >&2
    echo -e "  📝 Log detallado: ${LOG_FILE}" >&2
    echo "" >&2
    echo -e "${YELLOW}────────────────────────────────────────────────────────────────────${NC}" >&2
    echo -e "  💡 Para explorar el JSON:" >&2
    echo -e "     jq '.cuenta' ${OUTPUT_FILE}" >&2
    echo -e "     jq '.droplets.total_droplets' ${OUTPUT_FILE}" >&2
    echo -e "     jq '._metadata' ${OUTPUT_FILE}" >&2
    echo -e "${YELLOW}────────────────────────────────────────────────────────────────────${NC}" >&2
    echo "" >&2
    
    log "INFO" "Levantamiento completado en ${DURACION}s. Servicios: OK=${SERVICIOS_OK}, Vacíos=${SERVICIOS_VACIOS}, Error=${SERVICIOS_ERROR}"
}

# =============================================================================
# EJECUCIÓN
# =============================================================================

# Parsear argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --output-dir)
            OUTPUT_DIR="$2"
            OUTPUT_FILE="${OUTPUT_DIR}/digitalocean_inventario_${TIMESTAMP}.json"
            LOG_FILE="${OUTPUT_DIR}/levantamiento_do_${TIMESTAMP}.log"
            shift 2
            ;;
        --help|-h)
            echo "Uso: $0 [--output-dir /ruta/personalizada]"
            echo ""
            echo "Script de descubrimiento exhaustivo de infraestructura DigitalOcean."
            echo "Solo ejecuta comandos de lectura (read-only). No modifica nada."
            echo ""
            echo "Opciones:"
            echo "  --output-dir DIR    Directorio de salida (default: directorio actual)"
            echo "  --help, -h          Mostrar esta ayuda"
            echo ""
            echo "Requisitos:"
            echo "  - doctl instalado y autenticado"
            echo "  - jq instalado"
            echo "  - Token con permisos de lectura"
            exit 0
            ;;
        *)
            echo "Argumento desconocido: $1"
            echo "Usa --help para ver las opciones disponibles"
            exit 1
            ;;
    esac
done

# Crear directorio de salida si no existe
mkdir -p "${OUTPUT_DIR}"

# Ejecutar
main
