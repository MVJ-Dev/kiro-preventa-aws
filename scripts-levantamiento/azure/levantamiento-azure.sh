#!/bin/bash
#===============================================================================
# SCRIPT DE LEVANTAMIENTO COMPLETO DE INFRAESTRUCTURA AZURE
#===============================================================================
# Descripción: Descubre TODA la infraestructura Azure accesible con permisos
#              de lectura (Reader role). Genera un archivo JSON maestro.
# Autor: Mathias Von - Arquitecto Preventa AWS
# Fecha: 2026-07-13
# Uso: ./levantamiento-azure.sh
# Requisitos: Azure CLI (az) instalado y autenticado
# Permisos: Solo lectura (Reader role suficiente)
# Costo: $0 - Solo comandos de lectura
#===============================================================================

set -o pipefail

#===============================================================================
# CONFIGURACIÓN
#===============================================================================
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_DIR="$(pwd)/azure-discovery-${TIMESTAMP}"
OUTPUT_FILE="${OUTPUT_DIR}/azure-infraestructura-completa.json"
LOG_FILE="${OUTPUT_DIR}/levantamiento.log"
TEMP_DIR="${OUTPUT_DIR}/tmp"

# Colores para indicadores de progreso
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # Sin color

# Contadores de progreso
TOTAL_SERVICES=0
COMPLETED_SERVICES=0
ERRORS=0

#===============================================================================
# FUNCIONES UTILITARIAS
#===============================================================================

# Función para logging
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Indicador de progreso
progress() {
    local message="$1"
    COMPLETED_SERVICES=$((COMPLETED_SERVICES + 1))
    echo -e "${CYAN}[${COMPLETED_SERVICES}/${TOTAL_SERVICES}]${NC} ${GREEN}✓${NC} ${message}"
    log "INFO" "${message}"
}

# Indicador de error (no detiene la ejecución)
error_msg() {
    local message="$1"
    ERRORS=$((ERRORS + 1))
    echo -e "${CYAN}[${COMPLETED_SERVICES}/${TOTAL_SERVICES}]${NC} ${RED}✗${NC} ${message}"
    log "ERROR" "${message}"
}

# Indicador de sección
section() {
    local message="$1"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}▶ ${message}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "SECTION" "${message}"
}

# Ejecutar comando Azure con manejo de errores
# Retorna JSON o array vacío si falla
az_safe() {
    local description="$1"
    shift
    local result
    result=$(az "$@" --output json 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        log "WARN" "Comando falló o sin datos: ${description} -> az $*"
        echo "[]"
        return 1
    fi
    echo "$result"
    return 0
}

# Ejecutar comando Azure que retorna un objeto (no array)
az_safe_obj() {
    local description="$1"
    shift
    local result
    result=$(az "$@" --output json 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        log "WARN" "Comando falló o sin datos: ${description} -> az $*"
        echo "{}"
        return 1
    fi
    echo "$result"
    return 0
}

# Escribir resultado temporal por servicio
write_temp() {
    local service_key="$1"
    local data="$2"
    echo "$data" > "${TEMP_DIR}/${service_key}.json"
}

#===============================================================================
# VERIFICACIONES INICIALES
#===============================================================================

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║     LEVANTAMIENTO COMPLETO DE INFRAESTRUCTURA AZURE            ║"
echo "║     Solo lectura - Zero cost - Reader role                     ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Verificar que Azure CLI está instalado
if ! command -v az &> /dev/null; then
    echo -e "${RED}ERROR: Azure CLI (az) no está instalado.${NC}"
    echo "Instalar con: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
    exit 1
fi

# Verificar que hay sesión activa
if ! az account show &> /dev/null; then
    echo -e "${RED}ERROR: No hay sesión activa en Azure CLI.${NC}"
    echo "Ejecutar: az login"
    exit 1
fi

# Crear directorios de trabajo
mkdir -p "${OUTPUT_DIR}" "${TEMP_DIR}"

echo -e "${GREEN}Directorio de salida: ${OUTPUT_DIR}${NC}"
echo -e "${GREEN}Iniciando levantamiento...${NC}"
echo ""

# Calcular total de servicios para el indicador de progreso (dinámico)
TOTAL_SERVICES=$(grep -c '^\s*progress ' "$0")


#===============================================================================
# FUNCIÓN: INFORMACIÓN DE CONTEXTO (Tenant, usuario, suscripciones)
#===============================================================================
descubrir_contexto() {
    section "CONTEXTO: Tenant, Usuario, Suscripciones"

    # Usuario actual y tenant
    local account_info
    account_info=$(az_safe_obj "cuenta actual" account show)
    local tenant_id=$(echo "$account_info" | jq -r '.tenantId // "unknown"')

    # Información del usuario logueado
    local signed_in_user
    signed_in_user=$(az_safe_obj "usuario actual" ad signed-in-user show)

    # Listar TODAS las suscripciones accesibles
    local subscriptions
    subscriptions=$(az_safe "suscripciones" account list --all)

    local sub_count=$(echo "$subscriptions" | jq 'length')
    echo -e "  Tenant ID: ${CYAN}${tenant_id}${NC}"
    echo -e "  Suscripciones encontradas: ${CYAN}${sub_count}${NC}"

    # Guardar IDs de suscripciones para iteración posterior
    echo "$subscriptions" | jq -r '.[].id' > "${TEMP_DIR}/subscription_ids.txt"

    # Construir JSON de contexto
    local context_json
    context_json=$(jq -n \
        --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg tid "$tenant_id" \
        --argjson acct "$account_info" \
        --argjson user "$signed_in_user" \
        --argjson subs "$subscriptions" \
        '{
            timestamp_utc: $ts,
            tenant_id: $tid,
            current_account: $acct,
            signed_in_user: $user,
            subscriptions: $subs,
            total_subscriptions: ($subs | length)
        }')

    write_temp "00_contexto" "$context_json"
    progress "Contexto: tenant, usuario y ${sub_count} suscripciones"
}

#===============================================================================
# FUNCIÓN: AZURE AD / ENTRA ID
#===============================================================================
descubrir_entra_id() {
    section "ENTRA ID: Usuarios, Grupos, Service Principals, Apps"

    # Usuarios (puede haber muchos, limitamos a los primeros 999 por API)
    local users
    users=$(az_safe "usuarios AD" ad user list --all)
    progress "Entra ID: Usuarios ($(echo "$users" | jq 'length'))"

    # Grupos
    local groups
    groups=$(az_safe "grupos AD" ad group list --all)
    progress "Entra ID: Grupos ($(echo "$groups" | jq 'length'))"

    # Service Principals
    local service_principals
    service_principals=$(az_safe "service principals" ad sp list --all)
    progress "Entra ID: Service Principals ($(echo "$service_principals" | jq 'length'))"

    # App Registrations
    local app_registrations
    app_registrations=$(az_safe "app registrations" ad app list --all)
    progress "Entra ID: App Registrations ($(echo "$app_registrations" | jq 'length'))"

    # Construir JSON
    local entra_json
    entra_json=$(jq -n \
        --argjson users "$users" \
        --argjson groups "$groups" \
        --argjson sps "$service_principals" \
        --argjson apps "$app_registrations" \
        '{
            users: $users,
            groups: $groups,
            service_principals: $sps,
            app_registrations: $apps
        }')

    write_temp "01_entra_id" "$entra_json"
}

#===============================================================================
# FUNCIÓN: RESOURCE GROUPS (por suscripción)
#===============================================================================
descubrir_resource_groups() {
    section "RESOURCE GROUPS: Por suscripción"

    local all_rgs="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue
        local rgs
        rgs=$(az_safe "resource groups en ${sub_id}" group list --subscription "$sub_id")
        # Agregar subscription_id a cada RG
        rgs=$(echo "$rgs" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_rgs=$(echo "$all_rgs" "$rgs" | jq -s '.[0] + .[1]')
    done < "${TEMP_DIR}/subscription_ids.txt"

    write_temp "02_resource_groups" "$all_rgs"
    progress "Resource Groups ($(echo "$all_rgs" | jq 'length') total)"
}


#===============================================================================
# FUNCIÓN: VIRTUAL MACHINES (VMs, VMSS, Availability Sets)
#===============================================================================
descubrir_compute() {
    section "COMPUTE: VMs, VMSS, Availability Sets"

    local all_vms="[]"
    local all_vmss="[]"
    local all_avsets="[]"
    local all_disks="[]"
    local all_snapshots="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        # VMs con todos los detalles (instance view incluye estado)
        local vms
        vms=$(az_safe "VMs en ${sub_id}" vm list --subscription "$sub_id" --show-details)
        vms=$(echo "$vms" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_vms=$(echo "$all_vms" "$vms" | jq -s '.[0] + .[1]')

        # VMSS (Virtual Machine Scale Sets)
        local vmss
        vmss=$(az_safe "VMSS en ${sub_id}" vmss list --subscription "$sub_id")
        vmss=$(echo "$vmss" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_vmss=$(echo "$all_vmss" "$vmss" | jq -s '.[0] + .[1]')

        # Availability Sets (usando az resource list que no requiere --resource-group)
        local avsets
        avsets=$(az_safe "Availability Sets en ${sub_id}" resource list \
            --resource-type "Microsoft.Compute/availabilitySets" --subscription "$sub_id")
        avsets=$(echo "$avsets" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_avsets=$(echo "$all_avsets" "$avsets" | jq -s '.[0] + .[1]')

        # Managed Disks
        local disks
        disks=$(az_safe "discos en ${sub_id}" disk list --subscription "$sub_id")
        disks=$(echo "$disks" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_disks=$(echo "$all_disks" "$disks" | jq -s '.[0] + .[1]')

        # Snapshots
        local snapshots
        snapshots=$(az_safe "snapshots en ${sub_id}" snapshot list --subscription "$sub_id")
        snapshots=$(echo "$snapshots" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_snapshots=$(echo "$all_snapshots" "$snapshots" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    local compute_json
    compute_json=$(jq -n \
        --argjson vms "$all_vms" \
        --argjson vmss "$all_vmss" \
        --argjson avsets "$all_avsets" \
        --argjson disks "$all_disks" \
        --argjson snaps "$all_snapshots" \
        '{
            virtual_machines: $vms,
            vmss: $vmss,
            availability_sets: $avsets,
            managed_disks: $disks,
            snapshots: $snaps
        }')

    write_temp "03_compute" "$compute_json"
    progress "Compute: VMs ($(echo "$all_vms" | jq 'length')), VMSS ($(echo "$all_vmss" | jq 'length')), Discos ($(echo "$all_disks" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: AKS (Kubernetes)
#===============================================================================
descubrir_aks() {
    section "AKS: Clusters y Node Pools"

    local all_clusters="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        local clusters
        clusters=$(az_safe "AKS clusters en ${sub_id}" aks list --subscription "$sub_id")

        # Para cada cluster, obtener node pools detallados
        local enriched_clusters="[]"
        for cluster_name in $(echo "$clusters" | jq -r '.[].name // empty'); do
            local rg=$(echo "$clusters" | jq -r --arg n "$cluster_name" '.[] | select(.name==$n) | .resourceGroup')
            local cluster_detail
            cluster_detail=$(az_safe_obj "detalle AKS ${cluster_name}" aks show \
                --name "$cluster_name" --resource-group "$rg" --subscription "$sub_id")

            # Node pools
            local nodepools
            nodepools=$(az_safe "nodepools de ${cluster_name}" aks nodepool list \
                --cluster-name "$cluster_name" --resource-group "$rg" --subscription "$sub_id")

            cluster_detail=$(echo "$cluster_detail" | jq --argjson np "$nodepools" --arg sid "$sub_id" \
                '. + {node_pools_detail: $np, subscription_id: $sid}')
            enriched_clusters=$(echo "$enriched_clusters" | jq --argjson c "$cluster_detail" '. + [$c]')
        done

        all_clusters=$(echo "$all_clusters" "$enriched_clusters" | jq -s '.[0] + .[1]')
    done < "${TEMP_DIR}/subscription_ids.txt"

    write_temp "04_aks" "$all_clusters"
    progress "AKS: Clusters ($(echo "$all_clusters" | jq 'length'))"
}


#===============================================================================
# FUNCIÓN: APP SERVICE (Plans, Web Apps, Function Apps, Slots)
#===============================================================================
descubrir_app_service() {
    section "APP SERVICE: Plans, Web Apps, Function Apps"

    local all_plans="[]"
    local all_webapps="[]"
    local all_funcapps="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        # App Service Plans
        local plans
        plans=$(az_safe "app service plans en ${sub_id}" appservice plan list --subscription "$sub_id")
        plans=$(echo "$plans" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_plans=$(echo "$all_plans" "$plans" | jq -s '.[0] + .[1]')

        # Web Apps (incluye Function Apps con kind=functionapp)
        local webapps
        webapps=$(az_safe "web apps en ${sub_id}" webapp list --subscription "$sub_id")

        # Separar web apps de function apps
        local pure_webapps=$(echo "$webapps" | jq --arg sid "$sub_id" '[.[] | select(.kind // "" | test("functionapp") | not) | . + {subscription_id: $sid}]')
        local funcapps=$(echo "$webapps" | jq --arg sid "$sub_id" '[.[] | select(.kind // "" | test("functionapp")) | . + {subscription_id: $sid}]')

        # Obtener slots para cada webapp
        for app_name in $(echo "$pure_webapps" | jq -r '.[].name // empty'); do
            local rg=$(echo "$pure_webapps" | jq -r --arg n "$app_name" '.[] | select(.name==$n) | .resourceGroup')
            local slots
            slots=$(az_safe "slots de ${app_name}" webapp deployment slot list \
                --name "$app_name" --resource-group "$rg" --subscription "$sub_id")
            pure_webapps=$(echo "$pure_webapps" | jq --arg n "$app_name" --argjson s "$slots" \
                '[.[] | if .name == $n then . + {deployment_slots: $s} else . end]')
        done

        all_webapps=$(echo "$all_webapps" "$pure_webapps" | jq -s '.[0] + .[1]')
        all_funcapps=$(echo "$all_funcapps" "$funcapps" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    local app_service_json
    app_service_json=$(jq -n \
        --argjson plans "$all_plans" \
        --argjson webapps "$all_webapps" \
        --argjson funcapps "$all_funcapps" \
        '{
            app_service_plans: $plans,
            web_apps: $webapps,
            function_apps: $funcapps
        }')

    write_temp "05_app_service" "$app_service_json"
    progress "App Service: Plans ($(echo "$all_plans" | jq 'length')), WebApps ($(echo "$all_webapps" | jq 'length')), Functions ($(echo "$all_funcapps" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: CONTAINER APPS
#===============================================================================
descubrir_container_apps() {
    section "CONTAINER APPS: Environments y Apps"

    local all_envs="[]"
    local all_apps="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        # Container App Environments
        local envs
        envs=$(az_safe "container app environments en ${sub_id}" containerapp env list --subscription "$sub_id")
        envs=$(echo "$envs" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_envs=$(echo "$all_envs" "$envs" | jq -s '.[0] + .[1]')

        # Container Apps
        local apps
        apps=$(az_safe "container apps en ${sub_id}" containerapp list --subscription "$sub_id")
        apps=$(echo "$apps" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_apps=$(echo "$all_apps" "$apps" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    local container_apps_json
    container_apps_json=$(jq -n \
        --argjson envs "$all_envs" \
        --argjson apps "$all_apps" \
        '{
            environments: $envs,
            container_apps: $apps
        }')

    write_temp "06_container_apps" "$container_apps_json"
    progress "Container Apps: Envs ($(echo "$all_envs" | jq 'length')), Apps ($(echo "$all_apps" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: CONTAINER INSTANCES
#===============================================================================
descubrir_container_instances() {
    section "CONTAINER INSTANCES"

    local all_groups="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        local groups
        groups=$(az_safe "container instances en ${sub_id}" container list --subscription "$sub_id")
        groups=$(echo "$groups" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_groups=$(echo "$all_groups" "$groups" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    write_temp "07_container_instances" "$all_groups"
    progress "Container Instances ($(echo "$all_groups" | jq 'length'))"
}


#===============================================================================
# FUNCIÓN: NETWORKING (VNets, Subnets, NSGs, Route Tables, Peering, VPN, ER)
#===============================================================================
descubrir_networking() {
    section "NETWORKING: VNets, NSGs, Route Tables, Peering, VPN, ExpressRoute"

    local all_vnets="[]"
    local all_nsgs="[]"
    local all_route_tables="[]"
    local all_public_ips="[]"
    local all_vpn_gws="[]"
    local all_expressroute="[]"
    local all_nat_gws="[]"
    local all_private_endpoints="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        # VNets (incluyen subnets y peerings)
        local vnets
        vnets=$(az_safe "vnets en ${sub_id}" network vnet list --subscription "$sub_id")
        # Enriquecer cada VNet con subnets y peerings
        local enriched_vnets="[]"
        for vnet_name in $(echo "$vnets" | jq -r '.[].name // empty'); do
            local rg=$(echo "$vnets" | jq -r --arg n "$vnet_name" '.[] | select(.name==$n) | .resourceGroup')
            local vnet_detail
            vnet_detail=$(az_safe_obj "detalle vnet ${vnet_name}" network vnet show \
                --name "$vnet_name" --resource-group "$rg" --subscription "$sub_id")

            # Peerings
            local peerings
            peerings=$(az_safe "peerings de ${vnet_name}" network vnet peering list \
                --vnet-name "$vnet_name" --resource-group "$rg" --subscription "$sub_id")
            vnet_detail=$(echo "$vnet_detail" | jq --argjson p "$peerings" --arg sid "$sub_id" \
                '. + {peerings: $p, subscription_id: $sid}')
            enriched_vnets=$(echo "$enriched_vnets" | jq --argjson v "$vnet_detail" '. + [$v]')
        done
        all_vnets=$(echo "$all_vnets" "$enriched_vnets" | jq -s '.[0] + .[1]')

        # NSGs con reglas
        local nsgs
        nsgs=$(az_safe "NSGs en ${sub_id}" network nsg list --subscription "$sub_id")
        # Cada NSG ya incluye securityRules y defaultSecurityRules
        nsgs=$(echo "$nsgs" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_nsgs=$(echo "$all_nsgs" "$nsgs" | jq -s '.[0] + .[1]')

        # Route Tables
        local route_tables
        route_tables=$(az_safe "route tables en ${sub_id}" network route-table list --subscription "$sub_id")
        route_tables=$(echo "$route_tables" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_route_tables=$(echo "$all_route_tables" "$route_tables" | jq -s '.[0] + .[1]')

        # Public IPs
        local public_ips
        public_ips=$(az_safe "public IPs en ${sub_id}" network public-ip list --subscription "$sub_id")
        public_ips=$(echo "$public_ips" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_public_ips=$(echo "$all_public_ips" "$public_ips" | jq -s '.[0] + .[1]')

        # VPN Gateways (usando az resource list que no requiere --resource-group)
        local vpn_gws
        vpn_gws=$(az_safe "VPN gateways en ${sub_id}" resource list \
            --resource-type "Microsoft.Network/virtualNetworkGateways" --subscription "$sub_id")
        vpn_gws=$(echo "$vpn_gws" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_vpn_gws=$(echo "$all_vpn_gws" "$vpn_gws" | jq -s '.[0] + .[1]')

        # ExpressRoute circuits
        local expressroute
        expressroute=$(az_safe "ExpressRoute en ${sub_id}" network express-route list --subscription "$sub_id")
        expressroute=$(echo "$expressroute" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_expressroute=$(echo "$all_expressroute" "$expressroute" | jq -s '.[0] + .[1]')

        # NAT Gateways
        local nat_gws
        nat_gws=$(az_safe "NAT gateways en ${sub_id}" network nat gateway list --subscription "$sub_id")
        nat_gws=$(echo "$nat_gws" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_nat_gws=$(echo "$all_nat_gws" "$nat_gws" | jq -s '.[0] + .[1]')

        # Private Endpoints
        local private_endpoints
        private_endpoints=$(az_safe "private endpoints en ${sub_id}" network private-endpoint list --subscription "$sub_id")
        private_endpoints=$(echo "$private_endpoints" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_private_endpoints=$(echo "$all_private_endpoints" "$private_endpoints" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    local networking_json
    networking_json=$(jq -n \
        --argjson vnets "$all_vnets" \
        --argjson nsgs "$all_nsgs" \
        --argjson routes "$all_route_tables" \
        --argjson pips "$all_public_ips" \
        --argjson vpns "$all_vpn_gws" \
        --argjson er "$all_expressroute" \
        --argjson nat "$all_nat_gws" \
        --argjson pe "$all_private_endpoints" \
        '{
            virtual_networks: $vnets,
            network_security_groups: $nsgs,
            route_tables: $routes,
            public_ips: $pips,
            vpn_gateways: $vpns,
            expressroute_circuits: $er,
            nat_gateways: $nat,
            private_endpoints: $pe
        }')

    write_temp "08_networking" "$networking_json"
    progress "Networking: VNets ($(echo "$all_vnets" | jq 'length')), NSGs ($(echo "$all_nsgs" | jq 'length')), PIPs ($(echo "$all_public_ips" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: LOAD BALANCERS, APP GATEWAY, FRONT DOOR, TRAFFIC MANAGER
#===============================================================================
descubrir_load_balancing() {
    section "LOAD BALANCING: LBs, App Gateway, Front Door, Traffic Manager"

    local all_lbs="[]"
    local all_appgws="[]"
    local all_frontdoors="[]"
    local all_tm="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        # Load Balancers
        local lbs
        lbs=$(az_safe "load balancers en ${sub_id}" network lb list --subscription "$sub_id")
        lbs=$(echo "$lbs" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_lbs=$(echo "$all_lbs" "$lbs" | jq -s '.[0] + .[1]')

        # Application Gateways
        local appgws
        appgws=$(az_safe "app gateways en ${sub_id}" network application-gateway list --subscription "$sub_id")
        appgws=$(echo "$appgws" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_appgws=$(echo "$all_appgws" "$appgws" | jq -s '.[0] + .[1]')

        # Front Door
        local frontdoors
        frontdoors=$(az_safe "front doors en ${sub_id}" network front-door list --subscription "$sub_id")
        frontdoors=$(echo "$frontdoors" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_frontdoors=$(echo "$all_frontdoors" "$frontdoors" | jq -s '.[0] + .[1]')

        # Traffic Manager
        local tm_profiles
        tm_profiles=$(az_safe "traffic manager en ${sub_id}" network traffic-manager profile list --subscription "$sub_id")
        tm_profiles=$(echo "$tm_profiles" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_tm=$(echo "$all_tm" "$tm_profiles" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    local lb_json
    lb_json=$(jq -n \
        --argjson lbs "$all_lbs" \
        --argjson appgws "$all_appgws" \
        --argjson fd "$all_frontdoors" \
        --argjson tm "$all_tm" \
        '{
            load_balancers: $lbs,
            application_gateways: $appgws,
            front_doors: $fd,
            traffic_manager_profiles: $tm
        }')

    write_temp "09_load_balancing" "$lb_json"
    progress "Load Balancing: LBs ($(echo "$all_lbs" | jq 'length')), AppGW ($(echo "$all_appgws" | jq 'length')), FD ($(echo "$all_frontdoors" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: DNS Y FIREWALL
#===============================================================================
descubrir_dns_firewall() {
    section "DNS: Zonas y Registros / FIREWALL"

    local all_dns_zones="[]"
    local all_firewalls="[]"
    local all_fw_policies="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        # DNS Zones
        local dns_zones
        dns_zones=$(az_safe "DNS zones en ${sub_id}" network dns zone list --subscription "$sub_id")

        # Obtener registros por zona
        for zone_name in $(echo "$dns_zones" | jq -r '.[].name // empty'); do
            local rg=$(echo "$dns_zones" | jq -r --arg n "$zone_name" '.[] | select(.name==$n) | .resourceGroup')
            local records
            records=$(az_safe "registros DNS ${zone_name}" network dns record-set list \
                --zone-name "$zone_name" --resource-group "$rg" --subscription "$sub_id")
            dns_zones=$(echo "$dns_zones" | jq --arg n "$zone_name" --argjson r "$records" \
                '[.[] | if .name == $n then . + {records: $r} else . end]')
        done
        dns_zones=$(echo "$dns_zones" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_dns_zones=$(echo "$all_dns_zones" "$dns_zones" | jq -s '.[0] + .[1]')

        # Azure Firewall
        local firewalls
        firewalls=$(az_safe "firewalls en ${sub_id}" network firewall list --subscription "$sub_id")
        firewalls=$(echo "$firewalls" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_firewalls=$(echo "$all_firewalls" "$firewalls" | jq -s '.[0] + .[1]')

        # Firewall Policies
        local fw_policies
        fw_policies=$(az_safe "firewall policies en ${sub_id}" network firewall policy list --subscription "$sub_id")
        fw_policies=$(echo "$fw_policies" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_fw_policies=$(echo "$all_fw_policies" "$fw_policies" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    local dns_fw_json
    dns_fw_json=$(jq -n \
        --argjson zones "$all_dns_zones" \
        --argjson fw "$all_firewalls" \
        --argjson fwp "$all_fw_policies" \
        '{
            dns_zones: $zones,
            firewalls: $fw,
            firewall_policies: $fwp
        }')

    write_temp "10_dns_firewall" "$dns_fw_json"
    progress "DNS: Zonas ($(echo "$all_dns_zones" | jq 'length')), Firewalls ($(echo "$all_firewalls" | jq 'length'))"
}


#===============================================================================
# FUNCIÓN: BASES DE DATOS (SQL, Cosmos, PostgreSQL, MySQL, MariaDB, Redis, Synapse)
#===============================================================================
descubrir_databases() {
    section "DATABASES: SQL, Cosmos DB, PostgreSQL, MySQL, MariaDB, Redis, Synapse"

    local all_sql_servers="[]"
    local all_cosmos="[]"
    local all_pg_single="[]"
    local all_pg_flexible="[]"
    local all_mysql_single="[]"
    local all_mysql_flexible="[]"
    local all_mariadb="[]"
    local all_redis="[]"
    local all_synapse="[]"
    local all_sql_mi="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        # Azure SQL Servers + Databases + Elastic Pools
        local sql_servers
        sql_servers=$(az_safe "SQL servers en ${sub_id}" sql server list --subscription "$sub_id")
        for srv_name in $(echo "$sql_servers" | jq -r '.[].name // empty'); do
            local rg=$(echo "$sql_servers" | jq -r --arg n "$srv_name" '.[] | select(.name==$n) | .resourceGroup')

            # Databases del server
            local dbs
            dbs=$(az_safe "DBs en ${srv_name}" sql db list \
                --server "$srv_name" --resource-group "$rg" --subscription "$sub_id")

            # Elastic Pools
            local pools
            pools=$(az_safe "elastic pools en ${srv_name}" sql elastic-pool list \
                --server "$srv_name" --resource-group "$rg" --subscription "$sub_id")

            sql_servers=$(echo "$sql_servers" | jq --arg n "$srv_name" --argjson d "$dbs" --argjson p "$pools" \
                '[.[] | if .name == $n then . + {databases: $d, elastic_pools: $p} else . end]')
        done
        sql_servers=$(echo "$sql_servers" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_sql_servers=$(echo "$all_sql_servers" "$sql_servers" | jq -s '.[0] + .[1]')

        # SQL Managed Instances
        local sql_mi
        sql_mi=$(az_safe "SQL MI en ${sub_id}" sql mi list --subscription "$sub_id")
        sql_mi=$(echo "$sql_mi" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_sql_mi=$(echo "$all_sql_mi" "$sql_mi" | jq -s '.[0] + .[1]')

        # Cosmos DB Accounts
        local cosmos
        cosmos=$(az_safe "Cosmos DB en ${sub_id}" cosmosdb list --subscription "$sub_id")
        # Obtener databases y containers por cuenta
        for acct_name in $(echo "$cosmos" | jq -r '.[].name // empty'); do
            local rg=$(echo "$cosmos" | jq -r --arg n "$acct_name" '.[] | select(.name==$n) | .resourceGroup')
            local kind=$(echo "$cosmos" | jq -r --arg n "$acct_name" '.[] | select(.name==$n) | .kind')

            # SQL API databases (más común)
            local cosmos_dbs
            cosmos_dbs=$(az_safe "cosmos dbs en ${acct_name}" cosmosdb sql database list \
                --account-name "$acct_name" --resource-group "$rg" --subscription "$sub_id")

            cosmos=$(echo "$cosmos" | jq --arg n "$acct_name" --argjson d "$cosmos_dbs" \
                '[.[] | if .name == $n then . + {sql_databases: $d} else . end]')
        done
        cosmos=$(echo "$cosmos" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_cosmos=$(echo "$all_cosmos" "$cosmos" | jq -s '.[0] + .[1]')

        # PostgreSQL Single Server (legacy)
        local pg_single
        pg_single=$(az_safe "PostgreSQL single en ${sub_id}" postgres server list --subscription "$sub_id")
        pg_single=$(echo "$pg_single" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_pg_single=$(echo "$all_pg_single" "$pg_single" | jq -s '.[0] + .[1]')

        # PostgreSQL Flexible Server
        local pg_flexible
        pg_flexible=$(az_safe "PostgreSQL flexible en ${sub_id}" postgres flexible-server list --subscription "$sub_id")
        pg_flexible=$(echo "$pg_flexible" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_pg_flexible=$(echo "$all_pg_flexible" "$pg_flexible" | jq -s '.[0] + .[1]')

        # MySQL Single Server (legacy)
        local mysql_single
        mysql_single=$(az_safe "MySQL single en ${sub_id}" mysql server list --subscription "$sub_id")
        mysql_single=$(echo "$mysql_single" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_mysql_single=$(echo "$all_mysql_single" "$mysql_single" | jq -s '.[0] + .[1]')

        # MySQL Flexible Server
        local mysql_flexible
        mysql_flexible=$(az_safe "MySQL flexible en ${sub_id}" mysql flexible-server list --subscription "$sub_id")
        mysql_flexible=$(echo "$mysql_flexible" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_mysql_flexible=$(echo "$all_mysql_flexible" "$mysql_flexible" | jq -s '.[0] + .[1]')

        # MariaDB
        local mariadb
        mariadb=$(az_safe "MariaDB en ${sub_id}" mariadb server list --subscription "$sub_id")
        mariadb=$(echo "$mariadb" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_mariadb=$(echo "$all_mariadb" "$mariadb" | jq -s '.[0] + .[1]')

        # Azure Cache for Redis
        local redis
        redis=$(az_safe "Redis en ${sub_id}" redis list --subscription "$sub_id")
        redis=$(echo "$redis" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_redis=$(echo "$all_redis" "$redis" | jq -s '.[0] + .[1]')

        # Synapse Workspaces
        local synapse
        synapse=$(az_safe "Synapse en ${sub_id}" synapse workspace list --subscription "$sub_id")
        synapse=$(echo "$synapse" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_synapse=$(echo "$all_synapse" "$synapse" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    local db_json
    db_json=$(jq -n \
        --argjson sql "$all_sql_servers" \
        --argjson sqlmi "$all_sql_mi" \
        --argjson cosmos "$all_cosmos" \
        --argjson pg_s "$all_pg_single" \
        --argjson pg_f "$all_pg_flexible" \
        --argjson my_s "$all_mysql_single" \
        --argjson my_f "$all_mysql_flexible" \
        --argjson maria "$all_mariadb" \
        --argjson redis "$all_redis" \
        --argjson syn "$all_synapse" \
        '{
            azure_sql_servers: $sql,
            sql_managed_instances: $sqlmi,
            cosmos_db_accounts: $cosmos,
            postgresql_single_servers: $pg_s,
            postgresql_flexible_servers: $pg_f,
            mysql_single_servers: $my_s,
            mysql_flexible_servers: $my_f,
            mariadb_servers: $maria,
            redis_caches: $redis,
            synapse_workspaces: $syn
        }')

    write_temp "11_databases" "$db_json"
    progress "Databases: SQL ($(echo "$all_sql_servers" | jq 'length')), Cosmos ($(echo "$all_cosmos" | jq 'length')), PG ($(echo "$all_pg_flexible" | jq 'length')), Redis ($(echo "$all_redis" | jq 'length'))"
}


#===============================================================================
# FUNCIÓN: STORAGE ACCOUNTS (con containers, file shares, tables, queues)
#===============================================================================
descubrir_storage() {
    section "STORAGE: Accounts, Containers, File Shares, Tables, Queues"

    local all_accounts="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        local accounts
        accounts=$(az_safe "storage accounts en ${sub_id}" storage account list --subscription "$sub_id")

        # Enriquecer cada cuenta con containers, file shares, etc.
        for acct_name in $(echo "$accounts" | jq -r '.[].name // empty'); do
            local rg=$(echo "$accounts" | jq -r --arg n "$acct_name" '.[] | select(.name==$n) | .resourceGroup')

            # Obtener connection string no es posible con Reader, usar account key list tampoco
            # Usamos --auth-mode login para acceder sin keys
            local containers
            containers=$(az_safe "containers en ${acct_name}" storage container list \
                --account-name "$acct_name" --auth-mode login --subscription "$sub_id")

            local file_shares
            file_shares=$(az_safe "file shares en ${acct_name}" storage share list \
                --account-name "$acct_name" --auth-mode login --subscription "$sub_id")

            local tables
            tables=$(az_safe "tables en ${acct_name}" storage table list \
                --account-name "$acct_name" --auth-mode login --subscription "$sub_id")

            local queues
            queues=$(az_safe "queues en ${acct_name}" storage queue list \
                --account-name "$acct_name" --auth-mode login --subscription "$sub_id")

            accounts=$(echo "$accounts" | jq --arg n "$acct_name" \
                --argjson c "$containers" --argjson f "$file_shares" \
                --argjson t "$tables" --argjson q "$queues" \
                '[.[] | if .name == $n then . + {
                    blob_containers: $c,
                    file_shares: $f,
                    tables: $t,
                    queues: $q
                } else . end]')
        done

        accounts=$(echo "$accounts" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_accounts=$(echo "$all_accounts" "$accounts" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    write_temp "12_storage" "$all_accounts"
    progress "Storage Accounts ($(echo "$all_accounts" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: KEY VAULT (vaults, keys metadata, secrets names, certificates)
#===============================================================================
descubrir_keyvault() {
    section "KEY VAULT: Vaults, Keys, Secrets (nombres), Certificates"

    local all_vaults="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        local vaults
        vaults=$(az_safe "key vaults en ${sub_id}" keyvault list --subscription "$sub_id")

        # Enriquecer cada vault
        for vault_name in $(echo "$vaults" | jq -r '.[].name // empty'); do
            # Keys (solo metadata)
            local keys
            keys=$(az_safe "keys en ${vault_name}" keyvault key list --vault-name "$vault_name" --subscription "$sub_id")

            # Secrets (solo nombres, NO valores)
            local secrets
            secrets=$(az_safe "secrets en ${vault_name}" keyvault secret list --vault-name "$vault_name" --subscription "$sub_id")

            # Certificates
            local certs
            certs=$(az_safe "certs en ${vault_name}" keyvault certificate list --vault-name "$vault_name" --subscription "$sub_id")

            vaults=$(echo "$vaults" | jq --arg n "$vault_name" \
                --argjson k "$keys" --argjson s "$secrets" --argjson c "$certs" \
                '[.[] | if .name == $n then . + {
                    keys: $k,
                    secrets_metadata: $s,
                    certificates: $c
                } else . end]')
        done

        vaults=$(echo "$vaults" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_vaults=$(echo "$all_vaults" "$vaults" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    write_temp "13_keyvault" "$all_vaults"
    progress "Key Vaults ($(echo "$all_vaults" | jq 'length'))"
}


#===============================================================================
# FUNCIÓN: MONITORING (Monitor, Alerts, Log Analytics, App Insights)
#===============================================================================
descubrir_monitoring() {
    section "MONITORING: Action Groups, Alerts, Log Analytics, App Insights"

    local all_action_groups="[]"
    local all_alert_rules="[]"
    local all_log_analytics="[]"
    local all_app_insights="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        # Action Groups
        local action_groups
        action_groups=$(az_safe "action groups en ${sub_id}" monitor action-group list --subscription "$sub_id")
        action_groups=$(echo "$action_groups" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_action_groups=$(echo "$all_action_groups" "$action_groups" | jq -s '.[0] + .[1]')

        # Alert Rules (metric alerts)
        local alerts
        alerts=$(az_safe "metric alerts en ${sub_id}" monitor metrics alert list --subscription "$sub_id")
        alerts=$(echo "$alerts" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_alert_rules=$(echo "$all_alert_rules" "$alerts" | jq -s '.[0] + .[1]')

        # Log Analytics Workspaces
        local law
        law=$(az_safe "log analytics en ${sub_id}" monitor log-analytics workspace list --subscription "$sub_id")
        law=$(echo "$law" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_log_analytics=$(echo "$all_log_analytics" "$law" | jq -s '.[0] + .[1]')

        # Application Insights
        local app_insights
        app_insights=$(az_safe "app insights en ${sub_id}" monitor app-insights component list --subscription "$sub_id")
        app_insights=$(echo "$app_insights" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_app_insights=$(echo "$all_app_insights" "$app_insights" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    local monitoring_json
    monitoring_json=$(jq -n \
        --argjson ag "$all_action_groups" \
        --argjson alerts "$all_alert_rules" \
        --argjson law "$all_log_analytics" \
        --argjson ai "$all_app_insights" \
        '{
            action_groups: $ag,
            metric_alert_rules: $alerts,
            log_analytics_workspaces: $law,
            application_insights: $ai
        }')

    write_temp "14_monitoring" "$monitoring_json"
    progress "Monitoring: Action Groups ($(echo "$all_action_groups" | jq 'length')), LAW ($(echo "$all_log_analytics" | jq 'length')), App Insights ($(echo "$all_app_insights" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: MESSAGING (Service Bus, Event Hubs, Event Grid)
#===============================================================================
descubrir_messaging() {
    section "MESSAGING: Service Bus, Event Hubs, Event Grid"

    local all_sb_namespaces="[]"
    local all_eh_namespaces="[]"
    local all_eg_topics="[]"
    local all_eg_subs="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        # Service Bus Namespaces (con queues y topics)
        local sb_ns
        sb_ns=$(az_safe "service bus en ${sub_id}" servicebus namespace list --subscription "$sub_id")
        for ns_name in $(echo "$sb_ns" | jq -r '.[].name // empty'); do
            local rg=$(echo "$sb_ns" | jq -r --arg n "$ns_name" '.[] | select(.name==$n) | .resourceGroup')

            local queues
            queues=$(az_safe "SB queues en ${ns_name}" servicebus queue list \
                --namespace-name "$ns_name" --resource-group "$rg" --subscription "$sub_id")

            local topics
            topics=$(az_safe "SB topics en ${ns_name}" servicebus topic list \
                --namespace-name "$ns_name" --resource-group "$rg" --subscription "$sub_id")

            sb_ns=$(echo "$sb_ns" | jq --arg n "$ns_name" --argjson q "$queues" --argjson t "$topics" \
                '[.[] | if .name == $n then . + {queues: $q, topics: $t} else . end]')
        done
        sb_ns=$(echo "$sb_ns" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_sb_namespaces=$(echo "$all_sb_namespaces" "$sb_ns" | jq -s '.[0] + .[1]')

        # Event Hubs Namespaces (con event hubs)
        local eh_ns
        eh_ns=$(az_safe "event hubs en ${sub_id}" eventhubs namespace list --subscription "$sub_id")
        for ns_name in $(echo "$eh_ns" | jq -r '.[].name // empty'); do
            local rg=$(echo "$eh_ns" | jq -r --arg n "$ns_name" '.[] | select(.name==$n) | .resourceGroup')

            local hubs
            hubs=$(az_safe "hubs en ${ns_name}" eventhubs eventhub list \
                --namespace-name "$ns_name" --resource-group "$rg" --subscription "$sub_id")

            eh_ns=$(echo "$eh_ns" | jq --arg n "$ns_name" --argjson h "$hubs" \
                '[.[] | if .name == $n then . + {event_hubs: $h} else . end]')
        done
        eh_ns=$(echo "$eh_ns" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_eh_namespaces=$(echo "$all_eh_namespaces" "$eh_ns" | jq -s '.[0] + .[1]')

        # Event Grid Topics
        local eg_topics
        eg_topics=$(az_safe "event grid topics en ${sub_id}" eventgrid topic list --subscription "$sub_id")
        eg_topics=$(echo "$eg_topics" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_eg_topics=$(echo "$all_eg_topics" "$eg_topics" | jq -s '.[0] + .[1]')

        # Event Grid Subscriptions (a nivel de suscripción Azure)
        local eg_subs
        eg_subs=$(az_safe "event grid subs en ${sub_id}" eventgrid event-subscription list --subscription "$sub_id")
        eg_subs=$(echo "$eg_subs" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_eg_subs=$(echo "$all_eg_subs" "$eg_subs" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    local messaging_json
    messaging_json=$(jq -n \
        --argjson sb "$all_sb_namespaces" \
        --argjson eh "$all_eh_namespaces" \
        --argjson egt "$all_eg_topics" \
        --argjson egs "$all_eg_subs" \
        '{
            service_bus_namespaces: $sb,
            event_hubs_namespaces: $eh,
            event_grid_topics: $egt,
            event_grid_subscriptions: $egs
        }')

    write_temp "15_messaging" "$messaging_json"
    progress "Messaging: SB ($(echo "$all_sb_namespaces" | jq 'length')), EH ($(echo "$all_eh_namespaces" | jq 'length')), EG Topics ($(echo "$all_eg_topics" | jq 'length'))"
}


#===============================================================================
# FUNCIÓN: INTEGRATION (Logic Apps, API Management, Azure Functions)
#===============================================================================
descubrir_integration() {
    section "INTEGRATION: Logic Apps, API Management, Functions"

    local all_logic_apps="[]"
    local all_apim="[]"
    local all_functions="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        # Logic Apps
        local logic_apps
        logic_apps=$(az_safe "logic apps en ${sub_id}" logic workflow list --subscription "$sub_id")
        logic_apps=$(echo "$logic_apps" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_logic_apps=$(echo "$all_logic_apps" "$logic_apps" | jq -s '.[0] + .[1]')

        # API Management
        local apim
        apim=$(az_safe "APIM en ${sub_id}" apim list --subscription "$sub_id")
        # Obtener APIs de cada servicio APIM
        for apim_name in $(echo "$apim" | jq -r '.[].name // empty'); do
            local rg=$(echo "$apim" | jq -r --arg n "$apim_name" '.[] | select(.name==$n) | .resourceGroup')
            local apis
            apis=$(az_safe "APIs en ${apim_name}" apim api list \
                --service-name "$apim_name" --resource-group "$rg" --subscription "$sub_id")
            apim=$(echo "$apim" | jq --arg n "$apim_name" --argjson a "$apis" \
                '[.[] | if .name == $n then . + {apis: $a} else . end]')
        done
        apim=$(echo "$apim" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_apim=$(echo "$all_apim" "$apim" | jq -s '.[0] + .[1]')

        # Azure Functions (function apps ya capturados en app_service, aquí detallamos funciones)
        local func_apps
        func_apps=$(az_safe "function apps en ${sub_id}" functionapp list --subscription "$sub_id")
        for fa_name in $(echo "$func_apps" | jq -r '.[].name // empty'); do
            local rg=$(echo "$func_apps" | jq -r --arg n "$fa_name" '.[] | select(.name==$n) | .resourceGroup')
            local functions
            functions=$(az_safe "functions en ${fa_name}" functionapp function list \
                --name "$fa_name" --resource-group "$rg" --subscription "$sub_id")
            func_apps=$(echo "$func_apps" | jq --arg n "$fa_name" --argjson f "$functions" \
                '[.[] | if .name == $n then . + {functions: $f} else . end]')
        done
        func_apps=$(echo "$func_apps" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_functions=$(echo "$all_functions" "$func_apps" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    local integration_json
    integration_json=$(jq -n \
        --argjson la "$all_logic_apps" \
        --argjson apim "$all_apim" \
        --argjson func "$all_functions" \
        '{
            logic_apps: $la,
            api_management: $apim,
            function_apps_detail: $func
        }')

    write_temp "16_integration" "$integration_json"
    progress "Integration: Logic Apps ($(echo "$all_logic_apps" | jq 'length')), APIM ($(echo "$all_apim" | jq 'length')), Functions ($(echo "$all_functions" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: CONTAINER REGISTRY
#===============================================================================
descubrir_container_registry() {
    section "CONTAINER REGISTRY: Registries y Repositories"

    local all_registries="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        local registries
        registries=$(az_safe "ACR en ${sub_id}" acr list --subscription "$sub_id")

        # Obtener repositorios por registry
        for reg_name in $(echo "$registries" | jq -r '.[].name // empty'); do
            local repos
            repos=$(az_safe "repos en ${reg_name}" acr repository list --name "$reg_name" --subscription "$sub_id")
            registries=$(echo "$registries" | jq --arg n "$reg_name" --argjson r "$repos" \
                '[.[] | if .name == $n then . + {repositories: $r} else . end]')
        done

        registries=$(echo "$registries" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_registries=$(echo "$all_registries" "$registries" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    write_temp "17_container_registry" "$all_registries"
    progress "Container Registry ($(echo "$all_registries" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: AZURE DEVOPS (si está disponible)
#===============================================================================
descubrir_devops() {
    section "AZURE DEVOPS: Organizaciones y Proyectos"

    local devops_data="{}"

    # Verificar si la extensión devops está disponible
    if az devops -h &>/dev/null; then
        local projects
        projects=$(az_safe "devops projects" devops project list)
        devops_data=$(jq -n --argjson p "$projects" '{projects: $p}')
    else
        devops_data='{"note": "Extension azure-devops no instalada o no configurada"}'
        log "WARN" "Azure DevOps extension no disponible"
    fi

    write_temp "18_devops" "$devops_data"
    progress "Azure DevOps (verificado)"
}


#===============================================================================
# FUNCIÓN: SECURITY (Policy, Defender, RBAC)
#===============================================================================
descubrir_security() {
    section "SECURITY: Policy, Defender, RBAC"

    local all_policy_assignments="[]"
    local all_policy_definitions="[]"
    local all_role_assignments="[]"
    local all_defender_pricing="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        # Policy Assignments
        local policy_assignments
        policy_assignments=$(az_safe "policy assignments en ${sub_id}" policy assignment list --subscription "$sub_id")
        policy_assignments=$(echo "$policy_assignments" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_policy_assignments=$(echo "$all_policy_assignments" "$policy_assignments" | jq -s '.[0] + .[1]')

        # Policy Definitions (custom)
        local policy_defs
        policy_defs=$(az_safe "policy definitions en ${sub_id}" policy definition list \
            --subscription "$sub_id" --query "[?policyType=='Custom']")
        policy_defs=$(echo "$policy_defs" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_policy_definitions=$(echo "$all_policy_definitions" "$policy_defs" | jq -s '.[0] + .[1]')

        # Role Assignments (RBAC)
        local role_assignments
        role_assignments=$(az_safe "role assignments en ${sub_id}" role assignment list \
            --all --subscription "$sub_id")
        role_assignments=$(echo "$role_assignments" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_role_assignments=$(echo "$all_role_assignments" "$role_assignments" | jq -s '.[0] + .[1]')

        # Microsoft Defender for Cloud Pricing
        local defender
        defender=$(az_safe "defender pricing en ${sub_id}" security pricing list --subscription "$sub_id")
        defender=$(echo "$defender" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_defender_pricing=$(echo "$all_defender_pricing" "$defender" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    local security_json
    security_json=$(jq -n \
        --argjson pa "$all_policy_assignments" \
        --argjson pd "$all_policy_definitions" \
        --argjson ra "$all_role_assignments" \
        --argjson def "$all_defender_pricing" \
        '{
            policy_assignments: $pa,
            custom_policy_definitions: $pd,
            role_assignments: $ra,
            defender_pricing: $def
        }')

    write_temp "19_security" "$security_json"
    progress "Security: Policies ($(echo "$all_policy_assignments" | jq 'length')), RBAC ($(echo "$all_role_assignments" | jq 'length')), Defender"
}

#===============================================================================
# FUNCIÓN: BACKUP (Recovery Services Vaults, Policies, Protected Items)
#===============================================================================
descubrir_backup() {
    section "BACKUP: Recovery Services Vaults, Policies, Protected Items"

    local all_vaults="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        local vaults
        vaults=$(az_safe "recovery services vaults en ${sub_id}" resource list \
            --resource-type "Microsoft.RecoveryServices/vaults" --subscription "$sub_id")

        # Enriquecer cada vault con policies y protected items
        for vault_name in $(echo "$vaults" | jq -r '.[].name // empty'); do
            local rg=$(echo "$vaults" | jq -r --arg n "$vault_name" '.[] | select(.name==$n) | .resourceGroup')

            # Backup Policies
            local policies
            policies=$(az_safe "backup policies en ${vault_name}" backup policy list \
                --vault-name "$vault_name" --resource-group "$rg" --subscription "$sub_id")

            # Protected Items
            local items
            items=$(az_safe "protected items en ${vault_name}" backup item list \
                --vault-name "$vault_name" --resource-group "$rg" --subscription "$sub_id")

            vaults=$(echo "$vaults" | jq --arg n "$vault_name" --argjson p "$policies" --argjson i "$items" \
                '[.[] | if .name == $n then . + {backup_policies: $p, protected_items: $i} else . end]')
        done

        vaults=$(echo "$vaults" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_vaults=$(echo "$all_vaults" "$vaults" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    write_temp "20_backup" "$all_vaults"
    progress "Backup Vaults ($(echo "$all_vaults" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: DATA FACTORY Y DATABRICKS
#===============================================================================
descubrir_data_services() {
    section "DATA: Data Factory, Databricks"

    local all_adf="[]"
    local all_databricks="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        # Azure Data Factory
        local factories
        factories=$(az_safe "data factories en ${sub_id}" datafactory list --subscription "$sub_id")
        for factory_name in $(echo "$factories" | jq -r '.[].name // empty'); do
            local rg=$(echo "$factories" | jq -r --arg n "$factory_name" '.[] | select(.name==$n) | .resourceGroup')

            # Pipelines
            local pipelines
            pipelines=$(az_safe "pipelines en ${factory_name}" datafactory pipeline list \
                --factory-name "$factory_name" --resource-group "$rg" --subscription "$sub_id")

            # Linked Services
            local linked_services
            linked_services=$(az_safe "linked services en ${factory_name}" datafactory linked-service list \
                --factory-name "$factory_name" --resource-group "$rg" --subscription "$sub_id")

            factories=$(echo "$factories" | jq --arg n "$factory_name" \
                --argjson p "$pipelines" --argjson ls "$linked_services" \
                '[.[] | if .name == $n then . + {pipelines: $p, linked_services: $ls} else . end]')
        done
        factories=$(echo "$factories" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_adf=$(echo "$all_adf" "$factories" | jq -s '.[0] + .[1]')

        # Databricks Workspaces
        local databricks
        databricks=$(az_safe "databricks en ${sub_id}" databricks workspace list --subscription "$sub_id")
        databricks=$(echo "$databricks" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_databricks=$(echo "$all_databricks" "$databricks" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    local data_json
    data_json=$(jq -n \
        --argjson adf "$all_adf" \
        --argjson dbr "$all_databricks" \
        '{
            data_factories: $adf,
            databricks_workspaces: $dbr
        }')

    write_temp "21_data_services" "$data_json"
    progress "Data: ADF ($(echo "$all_adf" | jq 'length')), Databricks ($(echo "$all_databricks" | jq 'length'))"
}


#===============================================================================
# FUNCIÓN: CDN PROFILES
#===============================================================================
descubrir_cdn() {
    section "CDN: Profiles y Endpoints"

    local all_cdn="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        local cdn_profiles
        cdn_profiles=$(az_safe "CDN profiles en ${sub_id}" cdn profile list --subscription "$sub_id")
        cdn_profiles=$(echo "$cdn_profiles" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_cdn=$(echo "$all_cdn" "$cdn_profiles" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    write_temp "23_cdn" "$all_cdn"
    progress "CDN Profiles ($(echo "$all_cdn" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: PRIVATE DNS ZONES
#===============================================================================
descubrir_private_dns() {
    section "PRIVATE DNS: Zonas"

    local all_private_dns="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        local private_dns_zones
        private_dns_zones=$(az_safe "private DNS zones en ${sub_id}" network private-dns zone list --subscription "$sub_id")
        private_dns_zones=$(echo "$private_dns_zones" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_private_dns=$(echo "$all_private_dns" "$private_dns_zones" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    write_temp "24_private_dns" "$all_private_dns"
    progress "Private DNS Zones ($(echo "$all_private_dns" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: BASTION HOSTS
#===============================================================================
descubrir_bastion() {
    section "BASTION: Hosts"

    local all_bastions="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        # Bastion requiere iterar por RG, usamos az resource list
        local bastions
        bastions=$(az_safe "bastions en ${sub_id}" resource list \
            --resource-type "Microsoft.Network/bastionHosts" --subscription "$sub_id")
        bastions=$(echo "$bastions" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_bastions=$(echo "$all_bastions" "$bastions" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    write_temp "25_bastion" "$all_bastions"
    progress "Bastion Hosts ($(echo "$all_bastions" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: COGNITIVE SERVICES
#===============================================================================
descubrir_cognitive_services() {
    section "COGNITIVE SERVICES: Accounts"

    local all_cognitive="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        local cognitive
        cognitive=$(az_safe "cognitive services en ${sub_id}" cognitiveservices account list --subscription "$sub_id")
        cognitive=$(echo "$cognitive" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_cognitive=$(echo "$all_cognitive" "$cognitive" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    write_temp "26_cognitive_services" "$all_cognitive"
    progress "Cognitive Services ($(echo "$all_cognitive" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: STATIC WEB APPS
#===============================================================================
descubrir_static_web_apps() {
    section "STATIC WEB APPS"

    local all_swa="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        local swa
        swa=$(az_safe "static web apps en ${sub_id}" staticwebapp list --subscription "$sub_id")
        swa=$(echo "$swa" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_swa=$(echo "$all_swa" "$swa" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    write_temp "27_static_web_apps" "$all_swa"
    progress "Static Web Apps ($(echo "$all_swa" | jq 'length'))"
}

#===============================================================================
# FUNCIÓN: MANAGED IDENTITIES
#===============================================================================
descubrir_managed_identities() {
    section "MANAGED IDENTITIES: User-Assigned"

    local all_identities="[]"

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        local identities
        identities=$(az_safe "managed identities en ${sub_id}" identity list --subscription "$sub_id")
        identities=$(echo "$identities" | jq --arg sid "$sub_id" '[.[] | . + {subscription_id: $sid}]')
        all_identities=$(echo "$all_identities" "$identities" | jq -s '.[0] + .[1]')

    done < "${TEMP_DIR}/subscription_ids.txt"

    write_temp "28_managed_identities" "$all_identities"
    progress "Managed Identities ($(echo "$all_identities" | jq 'length'))"
}


#===============================================================================
# FUNCIÓN: COST MANAGEMENT (últimos 3 meses por resource group - GRATIS)
#===============================================================================
descubrir_costs() {
    section "COST MANAGEMENT: Costos por Resource Group (últimos 3 meses)"

    local all_costs="[]"
    local end_date=$(date -u +"%Y-%m-%dT00:00:00Z")
    local start_date=$(date -u -d "3 months ago" +"%Y-%m-%dT00:00:00Z" 2>/dev/null || \
                       date -u -v-3m +"%Y-%m-%dT00:00:00Z" 2>/dev/null || \
                       echo "$(date -u +%Y-%m-%d)T00:00:00Z")

    while IFS= read -r sub_id; do
        [ -z "$sub_id" ] && continue

        # Intentar obtener costos usando la API de cost management
        # Nota: Esto requiere al menos Cost Management Reader role
        local costs
        costs=$(az_safe "costos en ${sub_id}" costmanagement query \
            --type ActualCost \
            --timeframe Custom \
            --time-period "{\"from\":\"${start_date}\",\"to\":\"${end_date}\"}" \
            --dataset-aggregation "{\"totalCost\":{\"name\":\"Cost\",\"function\":\"Sum\"}}" \
            --dataset-grouping name=ResourceGroupName type=Dimension \
            --scope "subscriptions/${sub_id}")

        if [ "$costs" != "[]" ] && [ "$costs" != "{}" ]; then
            local cost_entry
            cost_entry=$(jq -n --arg sid "$sub_id" --argjson c "$costs" \
                '{subscription_id: $sid, cost_data: $c}')
            all_costs=$(echo "$all_costs" | jq --argjson e "$cost_entry" '. + [$e]')
        fi

    done < "${TEMP_DIR}/subscription_ids.txt"

    local cost_json
    cost_json=$(jq -n \
        --arg start "$start_date" \
        --arg end "$end_date" \
        --argjson costs "$all_costs" \
        '{
            period: {start: $start, end: $end},
            costs_by_subscription: $costs
        }')

    write_temp "22_costs" "$cost_json"
    progress "Cost Management (últimos 3 meses)"
}

#===============================================================================
# FUNCIÓN: ENSAMBLAR JSON MAESTRO
#===============================================================================
ensamblar_json_maestro() {
    section "ENSAMBLANDO JSON MAESTRO"

    # Leer todos los archivos temporales y construir el JSON final
    local contexto=$(cat "${TEMP_DIR}/00_contexto.json" 2>/dev/null || echo '{}')
    local entra_id=$(cat "${TEMP_DIR}/01_entra_id.json" 2>/dev/null || echo '{}')
    local resource_groups=$(cat "${TEMP_DIR}/02_resource_groups.json" 2>/dev/null || echo '[]')
    local compute=$(cat "${TEMP_DIR}/03_compute.json" 2>/dev/null || echo '{}')
    local aks=$(cat "${TEMP_DIR}/04_aks.json" 2>/dev/null || echo '[]')
    local app_service=$(cat "${TEMP_DIR}/05_app_service.json" 2>/dev/null || echo '{}')
    local container_apps=$(cat "${TEMP_DIR}/06_container_apps.json" 2>/dev/null || echo '{}')
    local container_instances=$(cat "${TEMP_DIR}/07_container_instances.json" 2>/dev/null || echo '[]')
    local networking=$(cat "${TEMP_DIR}/08_networking.json" 2>/dev/null || echo '{}')
    local load_balancing=$(cat "${TEMP_DIR}/09_load_balancing.json" 2>/dev/null || echo '{}')
    local dns_firewall=$(cat "${TEMP_DIR}/10_dns_firewall.json" 2>/dev/null || echo '{}')
    local databases=$(cat "${TEMP_DIR}/11_databases.json" 2>/dev/null || echo '{}')
    local storage=$(cat "${TEMP_DIR}/12_storage.json" 2>/dev/null || echo '[]')
    local keyvault=$(cat "${TEMP_DIR}/13_keyvault.json" 2>/dev/null || echo '[]')
    local monitoring=$(cat "${TEMP_DIR}/14_monitoring.json" 2>/dev/null || echo '{}')
    local messaging=$(cat "${TEMP_DIR}/15_messaging.json" 2>/dev/null || echo '{}')
    local integration=$(cat "${TEMP_DIR}/16_integration.json" 2>/dev/null || echo '{}')
    local container_registry=$(cat "${TEMP_DIR}/17_container_registry.json" 2>/dev/null || echo '[]')
    local devops=$(cat "${TEMP_DIR}/18_devops.json" 2>/dev/null || echo '{}')
    local security=$(cat "${TEMP_DIR}/19_security.json" 2>/dev/null || echo '{}')
    local backup=$(cat "${TEMP_DIR}/20_backup.json" 2>/dev/null || echo '[]')
    local data_services=$(cat "${TEMP_DIR}/21_data_services.json" 2>/dev/null || echo '{}')
    local costs=$(cat "${TEMP_DIR}/22_costs.json" 2>/dev/null || echo '{}')
    local cdn=$(cat "${TEMP_DIR}/23_cdn.json" 2>/dev/null || echo '[]')
    local private_dns=$(cat "${TEMP_DIR}/24_private_dns.json" 2>/dev/null || echo '[]')
    local bastion=$(cat "${TEMP_DIR}/25_bastion.json" 2>/dev/null || echo '[]')
    local cognitive_services=$(cat "${TEMP_DIR}/26_cognitive_services.json" 2>/dev/null || echo '[]')
    local static_web_apps=$(cat "${TEMP_DIR}/27_static_web_apps.json" 2>/dev/null || echo '[]')
    local managed_identities=$(cat "${TEMP_DIR}/28_managed_identities.json" 2>/dev/null || echo '[]')

    # Construir JSON maestro con jq
    jq -n \
        --argjson contexto "$contexto" \
        --argjson entra "$entra_id" \
        --argjson rgs "$resource_groups" \
        --argjson compute "$compute" \
        --argjson aks "$aks" \
        --argjson appsvc "$app_service" \
        --argjson ca "$container_apps" \
        --argjson ci "$container_instances" \
        --argjson net "$networking" \
        --argjson lb "$load_balancing" \
        --argjson dnsfw "$dns_firewall" \
        --argjson db "$databases" \
        --argjson stor "$storage" \
        --argjson kv "$keyvault" \
        --argjson mon "$monitoring" \
        --argjson msg "$messaging" \
        --argjson integ "$integration" \
        --argjson acr "$container_registry" \
        --argjson devops "$devops" \
        --argjson sec "$security" \
        --argjson bkp "$backup" \
        --argjson data "$data_services" \
        --argjson costs "$costs" \
        --argjson cdn "$cdn" \
        --argjson pdns "$private_dns" \
        --argjson bastion "$bastion" \
        --argjson cognitive "$cognitive_services" \
        --argjson swa "$static_web_apps" \
        --argjson mi "$managed_identities" \
        '{
            _metadata: {
                script: "levantamiento-azure.sh",
                version: "1.1.0",
                generated_at: $contexto.timestamp_utc,
                tenant_id: $contexto.tenant_id,
                total_subscriptions: $contexto.total_subscriptions
            },
            contexto: $contexto,
            entra_id: $entra,
            resource_groups: $rgs,
            compute: $compute,
            aks_clusters: $aks,
            app_service: $appsvc,
            container_apps: $ca,
            container_instances: $ci,
            networking: $net,
            load_balancing: $lb,
            dns_and_firewall: $dnsfw,
            databases: $db,
            storage_accounts: $stor,
            key_vaults: $kv,
            monitoring: $mon,
            messaging: $msg,
            integration: $integ,
            container_registries: $acr,
            azure_devops: $devops,
            security_and_compliance: $sec,
            backup: $bkp,
            data_services: $data,
            cdn_profiles: $cdn,
            private_dns_zones: $pdns,
            bastion_hosts: $bastion,
            cognitive_services: $cognitive,
            static_web_apps: $swa,
            managed_identities: $mi,
            cost_management: $costs
        }' > "${OUTPUT_FILE}"

    echo -e "${GREEN}✓ JSON maestro generado: ${OUTPUT_FILE}${NC}"
}

#===============================================================================
# FUNCIÓN: RESUMEN FINAL
#===============================================================================
mostrar_resumen() {
    local file_size=$(du -h "${OUTPUT_FILE}" | cut -f1)
    local duration=$((SECONDS / 60))
    local duration_sec=$((SECONDS % 60))

    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    RESUMEN DEL LEVANTAMIENTO                    ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} Archivo de salida: ${GREEN}${OUTPUT_FILE}${NC}"
    echo -e "${BLUE}║${NC} Tamaño: ${CYAN}${file_size}${NC}"
    echo -e "${BLUE}║${NC} Duración: ${CYAN}${duration}m ${duration_sec}s${NC}"
    echo -e "${BLUE}║${NC} Servicios procesados: ${CYAN}${COMPLETED_SERVICES}/${TOTAL_SERVICES}${NC}"
    echo -e "${BLUE}║${NC} Errores encontrados: ${RED}${ERRORS}${NC}"
    echo -e "${BLUE}║${NC} Log detallado: ${CYAN}${LOG_FILE}${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} ${YELLOW}Resumen de recursos descubiertos:${NC}"

    # Contar recursos principales del JSON
    if [ -f "${OUTPUT_FILE}" ]; then
        local vm_count=$(jq '.compute.virtual_machines | length' "${OUTPUT_FILE}" 2>/dev/null || echo "0")
        local vnet_count=$(jq '.networking.virtual_networks | length' "${OUTPUT_FILE}" 2>/dev/null || echo "0")
        local sql_count=$(jq '.databases.azure_sql_servers | length' "${OUTPUT_FILE}" 2>/dev/null || echo "0")
        local storage_count=$(jq '.storage_accounts | length' "${OUTPUT_FILE}" 2>/dev/null || echo "0")
        local aks_count=$(jq '.aks_clusters | length' "${OUTPUT_FILE}" 2>/dev/null || echo "0")
        local kv_count=$(jq '.key_vaults | length' "${OUTPUT_FILE}" 2>/dev/null || echo "0")

        echo -e "${BLUE}║${NC}   - Virtual Machines: ${CYAN}${vm_count}${NC}"
        echo -e "${BLUE}║${NC}   - Virtual Networks: ${CYAN}${vnet_count}${NC}"
        echo -e "${BLUE}║${NC}   - SQL Servers: ${CYAN}${sql_count}${NC}"
        echo -e "${BLUE}║${NC}   - Storage Accounts: ${CYAN}${storage_count}${NC}"
        echo -e "${BLUE}║${NC}   - AKS Clusters: ${CYAN}${aks_count}${NC}"
        echo -e "${BLUE}║${NC}   - Key Vaults: ${CYAN}${kv_count}${NC}"
    fi

    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Limpiar archivos temporales
    rm -rf "${TEMP_DIR}"
    echo -e "${GREEN}Archivos temporales eliminados.${NC}"
    echo -e "${GREEN}¡Levantamiento completado exitosamente!${NC}"
}

#===============================================================================
# EJECUCIÓN PRINCIPAL
#===============================================================================
main() {
    SECONDS=0

    echo -e "${YELLOW}Inicio: $(date)${NC}"
    echo ""

    # 1. Contexto (tenant, usuario, suscripciones)
    descubrir_contexto

    # 2. Entra ID (usuarios, grupos, SPs, apps)
    descubrir_entra_id

    # 3. Resource Groups
    descubrir_resource_groups

    # 4. Compute (VMs, VMSS, discos, snapshots)
    descubrir_compute

    # 5. AKS
    descubrir_aks

    # 6. App Service
    descubrir_app_service

    # 7. Container Apps
    descubrir_container_apps

    # 8. Container Instances
    descubrir_container_instances

    # 9. Networking
    descubrir_networking

    # 10. Load Balancing
    descubrir_load_balancing

    # 11. DNS y Firewall
    descubrir_dns_firewall

    # 12. Databases
    descubrir_databases

    # 13. Storage
    descubrir_storage

    # 14. Key Vault
    descubrir_keyvault

    # 15. Monitoring
    descubrir_monitoring

    # 16. Messaging
    descubrir_messaging

    # 17. Integration (Logic Apps, APIM, Functions)
    descubrir_integration

    # 18. Container Registry
    descubrir_container_registry

    # 19. Azure DevOps
    descubrir_devops

    # 20. Security (Policy, Defender, RBAC)
    descubrir_security

    # 21. Backup
    descubrir_backup

    # 22. Data Services (ADF, Databricks)
    descubrir_data_services

    # 23. CDN
    descubrir_cdn

    # 24. Private DNS
    descubrir_private_dns

    # 25. Bastion
    descubrir_bastion

    # 26. Cognitive Services
    descubrir_cognitive_services

    # 27. Static Web Apps
    descubrir_static_web_apps

    # 28. Managed Identities
    descubrir_managed_identities

    # 29. Cost Management
    descubrir_costs

    # Ensamblar JSON maestro
    ensamblar_json_maestro

    # Resumen final
    mostrar_resumen
}

# Ejecutar
main "$@"
