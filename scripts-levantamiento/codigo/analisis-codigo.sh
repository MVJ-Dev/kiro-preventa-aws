#!/bin/bash
# =============================================================================
# analisis-codigo.sh
# Script de análisis de repositorios de código para extracción de arquitectura
# y dependencias. Solo LECTURA - nunca modifica archivos.
#
# Uso: ./analisis-codigo.sh /ruta/al/repositorio [archivo_salida.json]
#
# Autor: Mathias Von - Arquitecto Preventa AWS
# Fecha: 2026-07-13
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURACIÓN Y VARIABLES GLOBALES
# =============================================================================

VERSION="1.0.0"
SCRIPT_NAME=$(basename "$0")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Colores para output en terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # Sin color

# Límites para repos grandes
MAX_FILES_SCAN=50000
MAX_FILE_SIZE_KB=1024
MAX_GREP_DEPTH=10

# =============================================================================
# FUNCIONES UTILITARIAS
# =============================================================================

# Muestra mensaje de progreso con timestamp (siempre a stderr para no contaminar JSON)
log_progress() {
    local step="$1"
    local msg="$2"
    echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} ${GREEN}[$step]${NC} $msg" >&2
}

# Muestra advertencia
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

# Muestra error y sale
log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Escapa texto para JSON (maneja comillas, backslashes, newlines, tabs)
json_escape() {
    local text="$1"
    text="${text//\\/\\\\}"
    text="${text//\"/\\\"}"
    text="${text//$'\n'/\\n}"
    text="${text//$'\t'/\\t}"
    text="${text//$'\r'/}"
    # Eliminar caracteres de control restantes
    text=$(echo "$text" | tr -d '\000-\011\013-\037')
    echo "$text"
}

# Convierte un array bash a array JSON de strings
to_json_array() {
    local arr=("$@")
    if [ ${#arr[@]} -eq 0 ]; then
        echo "[]"
        return
    fi
    local json="["
    local first=true
    for item in "${arr[@]}"; do
        # Saltar elementos vacíos
        [[ -z "$item" ]] && continue
        if [ "$first" = true ]; then
            first=false
        else
            json+=","
        fi
        json+="\"$(json_escape "$item")\""
    done
    # Si todos los items estaban vacíos
    if [ "$first" = true ]; then
        echo "[]"
        return
    fi
    json+="]"
    echo "$json"
}

# Verifica si un comando está disponible
cmd_exists() {
    command -v "$1" &>/dev/null
}

# Obtiene tamaño de archivo en KB de forma portable
file_size_kb() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local size
        size=$(wc -c < "$file" 2>/dev/null || echo "0")
        echo $(( size / 1024 ))
    else
        echo "0"
    fi
}

# Lee archivo si no excede el tamaño máximo
safe_read_file() {
    local file="$1"
    local max_kb="${2:-$MAX_FILE_SIZE_KB}"
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    local size_kb
    size_kb=$(file_size_kb "$file")
    if [[ $size_kb -gt $max_kb ]]; then
        log_warn "Archivo muy grande, omitido: $file (${size_kb}KB)"
        return 1
    fi
    cat "$file" 2>/dev/null
}

# Encuentra archivos excluyendo directorios comunes de dependencias/build
safe_find() {
    local path="$1"
    shift
    find "$path" \
        -not -path "*/node_modules/*" \
        -not -path "*/.git/*" \
        -not -path "*/vendor/*" \
        -not -path "*/__pycache__/*" \
        -not -path "*/.venv/*" \
        -not -path "*/venv/*" \
        -not -path "*/.env/*" \
        -not -path "*/dist/*" \
        -not -path "*/build/*" \
        -not -path "*/target/*" \
        -not -path "*/.terraform/*" \
        -not -path "*/.gradle/*" \
        -not -path "*/.m2/*" \
        -not -path "*/bin/*" \
        -not -path "*/obj/*" \
        "$@" 2>/dev/null || true
}

# Grep seguro que no falla en archivos binarios
safe_grep() {
    grep --text --binary-files=without-match "$@" 2>/dev/null || true
}

# =============================================================================
# VALIDACIÓN DE ENTRADA
# =============================================================================

show_usage() {
    echo "Uso: $SCRIPT_NAME <ruta_repositorio> [archivo_salida.json]"
    echo ""
    echo "Analiza un repositorio de código y genera un reporte JSON con:"
    echo "  - Infraestructura como código (Terraform, CloudFormation, K8s, Docker)"
    echo "  - Dependencias de aplicación (Node, Python, Java, Go, etc.)"
    echo "  - Configuración y conexiones"
    echo "  - Indicadores de arquitectura"
    echo "  - Estructura del código"
    echo "  - Patrones de comunicación"
    echo ""
    echo "Opciones:"
    echo "  -h, --help     Muestra esta ayuda"
    echo "  -v, --version  Muestra la versión"
    echo ""
    echo "Ejemplo:"
    echo "  $SCRIPT_NAME /home/user/mi-proyecto"
    echo "  $SCRIPT_NAME /home/user/mi-proyecto resultado.json"
}

# Parsear argumentos
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_usage
    exit 0
fi

if [[ "${1:-}" == "-v" || "${1:-}" == "--version" ]]; then
    echo "$SCRIPT_NAME v$VERSION"
    exit 0
fi

if [[ $# -lt 1 ]]; then
    show_usage
    exit 1
fi

REPO_PATH="$(realpath "$1" 2>/dev/null || echo "$1")"
OUTPUT_FILE="${2:-analisis-$(basename "$REPO_PATH")-$(date +%Y%m%d_%H%M%S).json}"

# Validaciones
if [[ ! -d "$REPO_PATH" ]]; then
    log_error "El directorio no existe: $REPO_PATH"
fi

if [[ ! -d "$REPO_PATH/.git" ]]; then
    log_warn "No es un repositorio git (no se encontró .git/). Continuando igualmente..."
fi

# Verificar herramientas necesarias
if ! cmd_exists jq; then
    log_warn "jq no está instalado. El JSON de salida no será formateado."
    HAS_JQ=false
else
    HAS_JQ=true
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Análisis de Repositorio de Código v${VERSION}${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "  Repositorio: ${GREEN}$REPO_PATH${NC}"
echo -e "  Salida:      ${GREEN}$OUTPUT_FILE${NC}"
echo -e "  Inicio:      ${GREEN}$TIMESTAMP${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Archivo temporal para construir el JSON
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT


# =============================================================================
# SECCIÓN 1: INFRAESTRUCTURA COMO CÓDIGO
# =============================================================================

analizar_terraform() {
    log_progress "IaC" "Analizando archivos Terraform..."
    local tf_files
    tf_files=$(safe_find "$REPO_PATH" -name "*.tf" -type f)
    
    if [[ -z "$tf_files" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local providers=()
    local resources=()
    local modules=()
    local variables=()
    local outputs=()
    local backends=()

    while IFS= read -r tf_file; do
        [[ -z "$tf_file" ]] && continue
        local content
        content=$(safe_read_file "$tf_file") || continue
        
        # Proveedores
        while IFS= read -r provider; do
            [[ -n "$provider" ]] && providers+=("$provider")
        done < <(echo "$content" | safe_grep -oP 'provider\s+"?\K[a-zA-Z0-9_-]+' | sort -u)
        
        # Recursos
        while IFS= read -r resource; do
            [[ -n "$resource" ]] && resources+=("$resource")
        done < <(echo "$content" | safe_grep -oP 'resource\s+"?\K[a-zA-Z0-9_]+' | sort -u)
        
        # Módulos
        while IFS= read -r module; do
            [[ -n "$module" ]] && modules+=("$module")
        done < <(echo "$content" | safe_grep -oP 'module\s+"?\K[a-zA-Z0-9_-]+' | sort -u)
        
        # Variables
        while IFS= read -r var; do
            [[ -n "$var" ]] && variables+=("$var")
        done < <(echo "$content" | safe_grep -oP 'variable\s+"?\K[a-zA-Z0-9_-]+' | sort -u)
        
        # Outputs
        while IFS= read -r output; do
            [[ -n "$output" ]] && outputs+=("$output")
        done < <(echo "$content" | safe_grep -oP 'output\s+"?\K[a-zA-Z0-9_-]+' | sort -u)
        
        # Backend
        while IFS= read -r backend; do
            [[ -n "$backend" ]] && backends+=("$backend")
        done < <(echo "$content" | safe_grep -oP 'backend\s+"?\K[a-zA-Z0-9_-]+' | sort -u)
        
    done <<< "$tf_files"

    # Deduplicar
    readarray -t providers < <(printf '%s\n' "${providers[@]}" 2>/dev/null | sort -u)
    readarray -t resources < <(printf '%s\n' "${resources[@]}" 2>/dev/null | sort -u)
    readarray -t modules < <(printf '%s\n' "${modules[@]}" 2>/dev/null | sort -u)
    readarray -t variables < <(printf '%s\n' "${variables[@]}" 2>/dev/null | sort -u)
    readarray -t outputs < <(printf '%s\n' "${outputs[@]}" 2>/dev/null | sort -u)
    readarray -t backends < <(printf '%s\n' "${backends[@]}" 2>/dev/null | sort -u)

    local num_files
    num_files=$(echo "$tf_files" | wc -l)

    cat <<EOF
{
  "encontrado": true,
  "num_archivos": $num_files,
  "providers": $(to_json_array "${providers[@]+"${providers[@]}"}"),
  "resources": $(to_json_array "${resources[@]+"${resources[@]}"}"),
  "modules": $(to_json_array "${modules[@]+"${modules[@]}"}"),
  "variables_count": ${#variables[@]},
  "outputs": $(to_json_array "${outputs[@]+"${outputs[@]}"}"),
  "backends": $(to_json_array "${backends[@]+"${backends[@]}"}")
}
EOF
}

analizar_cloudformation() {
    log_progress "IaC" "Analizando CloudFormation..."
    local cf_files
    cf_files=$(safe_find "$REPO_PATH" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) \
        -not -name "docker-compose*" -not -name "compose.*" -not -name "package*.json" \
        -not -path "*/.github/*" -not -path "*helm*" \
        | while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            # Debe tener AWSTemplateFormatVersion O al menos un recurso AWS::
            if grep -ql "AWSTemplateFormatVersion" "$f" 2>/dev/null; then
                echo "$f"
            elif grep -ql 'Type:.*AWS::' "$f" 2>/dev/null || grep -ql '"Type".*"AWS::' "$f" 2>/dev/null; then
                echo "$f"
            fi
        done)
    
    if [[ -z "$cf_files" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local resources=()
    local parameters=()
    local num_files=0

    while IFS= read -r cf_file; do
        [[ -z "$cf_file" ]] && continue
        ((num_files++))
        local content
        content=$(safe_read_file "$cf_file") || continue
        
        # Tipos de recursos AWS
        while IFS= read -r res; do
            [[ -n "$res" ]] && resources+=("$res")
        done < <(echo "$content" | safe_grep -oP 'Type:\s*\K(AWS::[a-zA-Z0-9:]+)' | sort -u)
        
        # Parámetros (nombres de sección Parameters)
        while IFS= read -r param; do
            [[ -n "$param" ]] && parameters+=("$param")
        done < <(echo "$content" | safe_grep -B0 -A0 'Type:\s*\(String\|Number\|List\|AWS::' | safe_grep -oP '^\s+\K[A-Za-z0-9]+(?=:)' | sort -u)
        
    done <<< "$cf_files"

    readarray -t resources < <(printf '%s\n' "${resources[@]}" 2>/dev/null | sort -u)

    cat <<EOF
{
  "encontrado": true,
  "num_archivos": $num_files,
  "recursos_aws": $(to_json_array "${resources[@]+"${resources[@]}"}"),
  "parametros_count": ${#parameters[@]}
}
EOF
}

analizar_kubernetes() {
    log_progress "IaC" "Analizando manifiestos Kubernetes..."
    local k8s_files
    k8s_files=$(safe_find "$REPO_PATH" -type f \( -name "*.yaml" -o -name "*.yml" \) \
        -not -name "docker-compose*" -not -name "compose.*" \
        | while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            if grep -ql "apiVersion:" "$f" 2>/dev/null && grep -ql "kind:" "$f" 2>/dev/null; then
                if grep -qP 'kind:\s*(Deployment|Service|Ingress|ConfigMap|StatefulSet|DaemonSet|Pod|Job|CronJob|Namespace|PersistentVolume)' "$f" 2>/dev/null; then
                    echo "$f"
                fi
            fi
        done)
    
    if [[ -z "$k8s_files" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local kinds=()
    local namespaces=()
    local images=()
    local num_files=0

    while IFS= read -r k8s_file; do
        [[ -z "$k8s_file" ]] && continue
        ((num_files++))
        local content
        content=$(safe_read_file "$k8s_file") || continue
        
        while IFS= read -r kind; do
            [[ -n "$kind" ]] && kinds+=("$kind")
        done < <(echo "$content" | safe_grep -oP 'kind:\s*\K[A-Za-z]+' | sort -u)
        
        while IFS= read -r ns; do
            [[ -n "$ns" ]] && namespaces+=("$ns")
        done < <(echo "$content" | safe_grep -oP 'namespace:\s*\K[a-zA-Z0-9_-]+' | sort -u)
        
        while IFS= read -r img; do
            [[ -n "$img" ]] && images+=("$img")
        done < <(echo "$content" | safe_grep -oP 'image:\s*\K[^\s"]+' | sort -u)
        
    done <<< "$k8s_files"

    readarray -t kinds < <(printf '%s\n' "${kinds[@]}" 2>/dev/null | sort | uniq -c | sort -rn | awk '{print $2 " (" $1 ")"}')
    readarray -t namespaces < <(printf '%s\n' "${namespaces[@]}" 2>/dev/null | sort -u)
    readarray -t images < <(printf '%s\n' "${images[@]}" 2>/dev/null | sort -u)

    cat <<EOF
{
  "encontrado": true,
  "num_archivos": $num_files,
  "kinds": $(to_json_array "${kinds[@]+"${kinds[@]}"}"),
  "namespaces": $(to_json_array "${namespaces[@]+"${namespaces[@]}"}"),
  "images": $(to_json_array "${images[@]+"${images[@]}"}")
}
EOF
}

analizar_docker_compose() {
    log_progress "IaC" "Analizando Docker Compose..."
    local compose_files
    compose_files=$(safe_find "$REPO_PATH" -type f \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" -o -name "compose.yml" -o -name "compose.yaml" \))
    
    if [[ -z "$compose_files" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local all_services=()
    local all_networks=()
    local all_volumes=()
    local all_env_vars=()
    local all_depends=()
    local compose_details="["
    local first_compose=true

    while IFS= read -r compose_file; do
        [[ -z "$compose_file" ]] && continue
        local content
        content=$(safe_read_file "$compose_file") || continue
        local rel_path="${compose_file#$REPO_PATH/}"
        
        # Servicios (líneas que están bajo 'services:' con indentación de 2 espacios)
        local services=()
        local in_services=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^services: ]]; then
                in_services=true
                continue
            fi
            if [[ "$in_services" == true && "$line" =~ ^[[:space:]]{2}[a-zA-Z] && ! "$line" =~ ^[[:space:]]{4} ]]; then
                local svc
                svc=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/:.*//')
                [[ -n "$svc" ]] && services+=("$svc") && all_services+=("$svc")
            fi
            if [[ "$in_services" == true && "$line" =~ ^[a-zA-Z] && ! "$line" =~ ^services ]]; then
                in_services=false
            fi
        done <<< "$content"
        
        # Networks
        while IFS= read -r net; do
            [[ -n "$net" ]] && all_networks+=("$net")
        done < <(echo "$content" | safe_grep -A100 "^networks:" | safe_grep -oP '^\s{2}\K[a-zA-Z0-9_-]+(?=:)' | head -20)
        
        # Volumes
        while IFS= read -r vol; do
            [[ -n "$vol" ]] && all_volumes+=("$vol")
        done < <(echo "$content" | safe_grep -A100 "^volumes:" | safe_grep -oP '^\s{2}\K[a-zA-Z0-9_-]+(?=:)' | head -20)
        
        # Variables de entorno (solo nombres)
        while IFS= read -r env_var; do
            [[ -n "$env_var" ]] && all_env_vars+=("$env_var")
        done < <(echo "$content" | safe_grep -oP '^\s+- \K[A-Z_][A-Z0-9_]*(?==)' | sort -u)
        while IFS= read -r env_var; do
            [[ -n "$env_var" ]] && all_env_vars+=("$env_var")
        done < <(echo "$content" | safe_grep -oP '^\s+\K[A-Z_][A-Z0-9_]*(?=:)' | sort -u)
        
        # depends_on
        while IFS= read -r dep; do
            [[ -n "$dep" ]] && all_depends+=("$dep")
        done < <(echo "$content" | safe_grep -A10 "depends_on:" | safe_grep -oP '^\s+- \K[a-zA-Z0-9_-]+' | sort -u)
        
    done <<< "$compose_files"

    readarray -t all_services < <(printf '%s\n' "${all_services[@]}" 2>/dev/null | sort -u)
    readarray -t all_networks < <(printf '%s\n' "${all_networks[@]}" 2>/dev/null | sort -u)
    readarray -t all_volumes < <(printf '%s\n' "${all_volumes[@]}" 2>/dev/null | sort -u)
    readarray -t all_env_vars < <(printf '%s\n' "${all_env_vars[@]}" 2>/dev/null | sort -u)
    readarray -t all_depends < <(printf '%s\n' "${all_depends[@]}" 2>/dev/null | sort -u)

    local num_files
    num_files=$(echo "$compose_files" | wc -l)

    cat <<EOF
{
  "encontrado": true,
  "num_archivos": $num_files,
  "services": $(to_json_array "${all_services[@]+"${all_services[@]}"}"),
  "networks": $(to_json_array "${all_networks[@]+"${all_networks[@]}"}"),
  "volumes": $(to_json_array "${all_volumes[@]+"${all_volumes[@]}"}"),
  "environment_variables": $(to_json_array "${all_env_vars[@]+"${all_env_vars[@]}"}"),
  "depends_on": $(to_json_array "${all_depends[@]+"${all_depends[@]}"}")
}
EOF
}

analizar_helm() {
    log_progress "IaC" "Analizando Helm Charts..."
    local chart_files
    chart_files=$(safe_find "$REPO_PATH" -name "Chart.yaml" -type f)
    
    if [[ -z "$chart_files" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local charts=()
    local num_charts=0

    while IFS= read -r chart_file; do
        [[ -z "$chart_file" ]] && continue
        ((num_charts++))
        local chart_dir
        chart_dir=$(dirname "$chart_file")
        local content
        content=$(safe_read_file "$chart_file") || continue
        
        local chart_name
        chart_name=$(echo "$content" | safe_grep -oP '^name:\s*\K.*' | head -1)
        [[ -n "$chart_name" ]] && charts+=("$chart_name")
    done <<< "$chart_files"

    # Buscar values.yaml
    local values_files
    values_files=$(safe_find "$REPO_PATH" -name "values.yaml" -o -name "values.yml" | wc -l)

    cat <<EOF
{
  "encontrado": true,
  "num_charts": $num_charts,
  "charts": $(to_json_array "${charts[@]+"${charts[@]}"}"),
  "values_files": $values_files
}
EOF
}

analizar_ansible() {
    log_progress "IaC" "Analizando Ansible..."
    local ansible_files
    ansible_files=$(safe_find "$REPO_PATH" -type f \( -name "playbook*.yml" -o -name "playbook*.yaml" -o -name "site.yml" -o -name "main.yml" -o -path "*/roles/*" -o -path "*/ansible/*" \) \
        | while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            if grep -ql "hosts:\|tasks:\|roles:" "$f" 2>/dev/null; then
                echo "$f"
            fi
        done)
    
    # También buscar ansible.cfg
    local ansible_cfg
    ansible_cfg=$(safe_find "$REPO_PATH" -name "ansible.cfg" -type f | head -1)
    
    if [[ -z "$ansible_files" && -z "$ansible_cfg" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local roles=()
    local roles_dir
    roles_dir=$(safe_find "$REPO_PATH" -type d -name "roles" | head -1)
    if [[ -n "$roles_dir" ]]; then
        while IFS= read -r role; do
            [[ -n "$role" ]] && roles+=("$(basename "$role")")
        done < <(find "$roles_dir" -maxdepth 1 -type d | tail -n +2)
    fi

    local num_playbooks
    num_playbooks=$(echo "$ansible_files" | grep -c "." 2>/dev/null || echo "0")

    cat <<EOF
{
  "encontrado": true,
  "num_playbooks": $num_playbooks,
  "roles": $(to_json_array "${roles[@]+"${roles[@]}"}"),
  "tiene_ansible_cfg": $([ -n "$ansible_cfg" ] && echo "true" || echo "false")
}
EOF
}

analizar_pulumi() {
    log_progress "IaC" "Analizando Pulumi..."
    local pulumi_files
    pulumi_files=$(safe_find "$REPO_PATH" -name "Pulumi.yaml" -o -name "Pulumi.yml" -type f)
    
    if [[ -z "$pulumi_files" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local projects=()
    local runtimes=()

    while IFS= read -r pf; do
        [[ -z "$pf" ]] && continue
        local content
        content=$(safe_read_file "$pf") || continue
        
        local name
        name=$(echo "$content" | safe_grep -oP '^name:\s*\K.*' | head -1)
        [[ -n "$name" ]] && projects+=("$name")
        
        local runtime
        runtime=$(echo "$content" | safe_grep -oP '^runtime:\s*\K.*' | head -1)
        [[ -n "$runtime" ]] && runtimes+=("$runtime")
    done <<< "$pulumi_files"

    cat <<EOF
{
  "encontrado": true,
  "projects": $(to_json_array "${projects[@]+"${projects[@]}"}"),
  "runtimes": $(to_json_array "${runtimes[@]+"${runtimes[@]}"}")
}
EOF
}

# =============================================================================
# SECCIÓN 2: DEPENDENCIAS DE APLICACIÓN
# =============================================================================

analizar_nodejs() {
    log_progress "Deps" "Analizando Node.js (package.json)..."
    local pkg_files
    pkg_files=$(safe_find "$REPO_PATH" -name "package.json" -type f)
    
    if [[ -z "$pkg_files" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local all_deps=()
    local all_dev_deps=()
    local all_scripts=()
    local packages_info="["
    local first=true
    local num_files=0

    while IFS= read -r pkg_file; do
        [[ -z "$pkg_file" ]] && continue
        ((num_files++))
        local content
        content=$(safe_read_file "$pkg_file") || continue
        local rel_path="${pkg_file#$REPO_PATH/}"
        
        # Extraer nombre del paquete
        local pkg_name
        pkg_name=$(echo "$content" | safe_grep -oP '"name"\s*:\s*"\K[^"]+' | head -1)
        
        # Dependencias - combinar todas las líneas y usar grep para extraer bloque
        local deps=()
        local content_oneline
        content_oneline=$(echo "$content" | tr -d '\n' | tr -s ' ')
        while IFS= read -r dep; do
            [[ -n "$dep" ]] && deps+=("$dep") && all_deps+=("$dep")
        done < <(echo "$content_oneline" | grep -oP '"dependencies"\s*:\s*\{[^}]*' | grep -oP '"\K[@a-zA-Z0-9_./-]+(?="\s*:\s*")' | grep -v "^dependencies$")
        
        # DevDependencies
        local dev_deps=()
        while IFS= read -r dep; do
            [[ -n "$dep" ]] && dev_deps+=("$dep") && all_dev_deps+=("$dep")
        done < <(echo "$content_oneline" | grep -oP '"devDependencies"\s*:\s*\{[^}]*' | grep -oP '"\K[@a-zA-Z0-9_./-]+(?="\s*:\s*")' | grep -v "^devDependencies$")
        
        # Scripts
        while IFS= read -r script; do
            [[ -n "$script" ]] && all_scripts+=("$script")
        done < <(echo "$content_oneline" | grep -oP '"scripts"\s*:\s*\{[^}]*' | grep -oP '"\K[a-zA-Z0-9:_.-]+(?="\s*:\s*")' | grep -v "^scripts$")
        
        if [ "$first" = true ]; then first=false; else packages_info+=","; fi
        packages_info+="{\"path\":\"$(json_escape "$rel_path")\",\"name\":\"$(json_escape "${pkg_name:-unknown}")\",\"deps\":${#deps[@]},\"devDeps\":${#dev_deps[@]}}"
        
    done <<< "$pkg_files"
    packages_info+="]"

    readarray -t all_deps < <(printf '%s\n' "${all_deps[@]}" 2>/dev/null | sort -u)
    readarray -t all_dev_deps < <(printf '%s\n' "${all_dev_deps[@]}" 2>/dev/null | sort -u)
    readarray -t all_scripts < <(printf '%s\n' "${all_scripts[@]}" 2>/dev/null | sort -u)

    cat <<EOF
{
  "encontrado": true,
  "num_package_json": $num_files,
  "dependencias_unicas": ${#all_deps[@]},
  "dev_dependencias_unicas": ${#all_dev_deps[@]},
  "scripts": $(to_json_array "${all_scripts[@]+"${all_scripts[@]}"}"),
  "principales_deps": $(to_json_array "${all_deps[@]:0:30}"),
  "paquetes": $packages_info
}
EOF
}

analizar_python() {
    log_progress "Deps" "Analizando Python..."
    local requirements_files
    requirements_files=$(safe_find "$REPO_PATH" -type f \( -name "requirements*.txt" -o -name "Pipfile" -o -name "pyproject.toml" -o -name "setup.py" -o -name "setup.cfg" \))
    
    if [[ -z "$requirements_files" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local all_deps=()
    local frameworks=()
    local has_pipfile=false
    local has_pyproject=false

    while IFS= read -r req_file; do
        [[ -z "$req_file" ]] && continue
        local content
        content=$(safe_read_file "$req_file") || continue
        local basename_f
        basename_f=$(basename "$req_file")
        
        case "$basename_f" in
            requirements*.txt)
                while IFS= read -r dep; do
                    dep=$(echo "$dep" | sed 's/[>=<!\[].*//;s/#.*//' | tr -d '[:space:]')
                    [[ -n "$dep" && ! "$dep" =~ ^- ]] && all_deps+=("$dep")
                done <<< "$content"
                ;;
            Pipfile)
                has_pipfile=true
                while IFS= read -r dep; do
                    [[ -n "$dep" ]] && all_deps+=("$dep")
                done < <(echo "$content" | safe_grep -oP '^\K[a-zA-Z0-9_-]+(?=\s*=)' | grep -v "python_version\|name\|url\|verify_ssl")
                ;;
            pyproject.toml)
                has_pyproject=true
                while IFS= read -r dep; do
                    dep=$(echo "$dep" | sed 's/[>=<!\[].*//;s/"//g;s/,//g' | tr -d '[:space:]')
                    [[ -n "$dep" ]] && all_deps+=("$dep")
                done < <(echo "$content" | safe_grep -oP '"\K[a-zA-Z0-9_-]+' | head -50)
                ;;
        esac
    done <<< "$requirements_files"

    readarray -t all_deps < <(printf '%s\n' "${all_deps[@]}" 2>/dev/null | sort -u)

    # Detectar frameworks
    for dep in "${all_deps[@]}"; do
        case "$dep" in
            django|Django) frameworks+=("Django") ;;
            flask|Flask) frameworks+=("Flask") ;;
            fastapi|FastAPI) frameworks+=("FastAPI") ;;
            celery|Celery) frameworks+=("Celery") ;;
            boto3) frameworks+=("AWS SDK (boto3)") ;;
            tensorflow|torch|pytorch) frameworks+=("ML/AI") ;;
        esac
    done

    cat <<EOF
{
  "encontrado": true,
  "dependencias": $(to_json_array "${all_deps[@]+"${all_deps[@]}"}"),
  "num_dependencias": ${#all_deps[@]},
  "frameworks_detectados": $(to_json_array "${frameworks[@]+"${frameworks[@]}"}"),
  "tiene_pipfile": $has_pipfile,
  "tiene_pyproject": $has_pyproject
}
EOF
}

analizar_java() {
    log_progress "Deps" "Analizando Java (Maven/Gradle)..."
    local pom_files
    pom_files=$(safe_find "$REPO_PATH" -name "pom.xml" -type f)
    local gradle_files
    gradle_files=$(safe_find "$REPO_PATH" -type f \( -name "build.gradle" -o -name "build.gradle.kts" \))
    
    if [[ -z "$pom_files" && -z "$gradle_files" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local dependencies=()
    local plugins=()
    local java_version=""
    local spring_boot=false
    local build_tool=""

    # Analizar Maven
    if [[ -n "$pom_files" ]]; then
        build_tool="maven"
        while IFS= read -r pom_file; do
            [[ -z "$pom_file" ]] && continue
            local content
            content=$(safe_read_file "$pom_file") || continue
            
            # GroupId:ArtifactId
            while IFS= read -r dep; do
                [[ -n "$dep" ]] && dependencies+=("$dep")
            done < <(echo "$content" | safe_grep -oP '<artifactId>\K[^<]+' | sort -u | head -50)
            
            # Java version
            if [[ -z "$java_version" ]]; then
                java_version=$(echo "$content" | safe_grep -oP '<java.version>\K[^<]+' | head -1)
                [[ -z "$java_version" ]] && java_version=$(echo "$content" | safe_grep -oP '<maven.compiler.source>\K[^<]+' | head -1)
            fi
            
            # Spring Boot
            if echo "$content" | safe_grep -q "spring-boot"; then
                spring_boot=true
            fi
        done <<< "$pom_files"
    fi

    # Analizar Gradle
    if [[ -n "$gradle_files" ]]; then
        build_tool="${build_tool:+$build_tool+}gradle"
        while IFS= read -r gradle_file; do
            [[ -z "$gradle_file" ]] && continue
            local content
            content=$(safe_read_file "$gradle_file") || continue
            
            while IFS= read -r dep; do
                [[ -n "$dep" ]] && dependencies+=("$dep")
            done < <(echo "$content" | safe_grep -oP "implementation\s*['\"]?\K[^'\")+]+" | sort -u | head -50)
            while IFS= read -r dep; do
                [[ -n "$dep" ]] && dependencies+=("$dep")
            done < <(echo "$content" | safe_grep -oP "compile\s*['\"]?\K[^'\")+]+" | sort -u | head -50)
            
            if echo "$content" | safe_grep -q "spring-boot\|org.springframework.boot"; then
                spring_boot=true
            fi
        done <<< "$gradle_files"
    fi

    readarray -t dependencies < <(printf '%s\n' "${dependencies[@]}" 2>/dev/null | sort -u)

    cat <<EOF
{
  "encontrado": true,
  "build_tool": "$build_tool",
  "java_version": "$java_version",
  "spring_boot": $spring_boot,
  "num_dependencias": ${#dependencies[@]},
  "dependencias": $(to_json_array "${dependencies[@]:0:40}")
}
EOF
}

analizar_go() {
    log_progress "Deps" "Analizando Go..."
    local go_mod_files
    go_mod_files=$(safe_find "$REPO_PATH" -name "go.mod" -type f)
    
    if [[ -z "$go_mod_files" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local modules=()
    local go_version=""
    local module_name=""

    while IFS= read -r go_mod; do
        [[ -z "$go_mod" ]] && continue
        local content
        content=$(safe_read_file "$go_mod") || continue
        
        [[ -z "$module_name" ]] && module_name=$(echo "$content" | safe_grep -oP '^module\s+\K.*' | head -1)
        [[ -z "$go_version" ]] && go_version=$(echo "$content" | safe_grep -oP '^go\s+\K[0-9.]+' | head -1)
        
        while IFS= read -r mod; do
            [[ -n "$mod" ]] && modules+=("$mod")
        done < <(echo "$content" | safe_grep -oP '^\s+\K[a-zA-Z0-9./\-]+(?=\s+v)' | sort -u)
    done <<< "$go_mod_files"

    readarray -t modules < <(printf '%s\n' "${modules[@]}" 2>/dev/null | sort -u)

    cat <<EOF
{
  "encontrado": true,
  "module": "$(json_escape "$module_name")",
  "go_version": "$go_version",
  "num_dependencias": ${#modules[@]},
  "dependencias": $(to_json_array "${modules[@]:0:40}")
}
EOF
}

analizar_ruby() {
    log_progress "Deps" "Analizando Ruby..."
    local gemfile
    gemfile=$(safe_find "$REPO_PATH" -name "Gemfile" -type f | head -1)
    
    if [[ -z "$gemfile" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local gems=()
    local content
    content=$(safe_read_file "$gemfile") || { echo '{"encontrado": false}'; return; }
    
    while IFS= read -r gem; do
        [[ -n "$gem" ]] && gems+=("$gem")
    done < <(echo "$content" | safe_grep -oP "gem\s+['\"]?\K[^'\",:)]+")

    local rails=false
    printf '%s\n' "${gems[@]}" | grep -qi "rails" && rails=true

    cat <<EOF
{
  "encontrado": true,
  "num_gems": ${#gems[@]},
  "rails": $rails,
  "gems": $(to_json_array "${gems[@]+"${gems[@]}"}")
}
EOF
}

analizar_php() {
    log_progress "Deps" "Analizando PHP..."
    local composer_file
    composer_file=$(safe_find "$REPO_PATH" -name "composer.json" -type f | head -1)
    
    if [[ -z "$composer_file" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local content
    content=$(safe_read_file "$composer_file") || { echo '{"encontrado": false}'; return; }
    
    local deps=()
    while IFS= read -r dep; do
        [[ -n "$dep" && "$dep" != "php" ]] && deps+=("$dep")
    done < <(echo "$content" | safe_grep -oP '"require"\s*:\s*\{[^}]*' | safe_grep -oP '"\K[^"]+(?="\s*:)' | grep -v "^php$\|^ext-")

    local laravel=false
    printf '%s\n' "${deps[@]}" | grep -qi "laravel" && laravel=true

    cat <<EOF
{
  "encontrado": true,
  "num_dependencias": ${#deps[@]},
  "laravel": $laravel,
  "dependencias": $(to_json_array "${deps[@]+"${deps[@]}"}")
}
EOF
}

analizar_rust() {
    log_progress "Deps" "Analizando Rust..."
    local cargo_files
    cargo_files=$(safe_find "$REPO_PATH" -name "Cargo.toml" -type f)
    
    if [[ -z "$cargo_files" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local crates=()
    local workspace=false

    while IFS= read -r cargo_file; do
        [[ -z "$cargo_file" ]] && continue
        local content
        content=$(safe_read_file "$cargo_file") || continue
        
        echo "$content" | safe_grep -q "\[workspace\]" && workspace=true
        
        # Dependencias bajo [dependencies]
        local in_deps=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^\[dependencies\] ]]; then
                in_deps=true
                continue
            fi
            if [[ "$line" =~ ^\[ ]]; then
                in_deps=false
                continue
            fi
            if [[ "$in_deps" == true && "$line" =~ ^[a-zA-Z] ]]; then
                local crate
                crate=$(echo "$line" | cut -d'=' -f1 | tr -d '[:space:]')
                [[ -n "$crate" ]] && crates+=("$crate")
            fi
        done <<< "$content"
    done <<< "$cargo_files"

    readarray -t crates < <(printf '%s\n' "${crates[@]}" 2>/dev/null | sort -u)

    cat <<EOF
{
  "encontrado": true,
  "workspace": $workspace,
  "num_crates": ${#crates[@]},
  "dependencias": $(to_json_array "${crates[@]+"${crates[@]}"}")
}
EOF
}

analizar_dotnet() {
    log_progress "Deps" "Analizando .NET..."
    local csproj_files
    csproj_files=$(safe_find "$REPO_PATH" -type f \( -name "*.csproj" -o -name "*.fsproj" -o -name "*.vbproj" \))
    
    if [[ -z "$csproj_files" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local packages=()
    local frameworks=()
    local num_projects=0

    while IFS= read -r proj_file; do
        [[ -z "$proj_file" ]] && continue
        ((num_projects++))
        local content
        content=$(safe_read_file "$proj_file") || continue
        
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] && packages+=("$pkg")
        done < <(echo "$content" | safe_grep -oP 'PackageReference\s+Include="\K[^"]+' | sort -u)
        
        while IFS= read -r fw; do
            [[ -n "$fw" ]] && frameworks+=("$fw")
        done < <(echo "$content" | safe_grep -oP '<TargetFramework>\K[^<]+' | sort -u)
    done <<< "$csproj_files"

    readarray -t packages < <(printf '%s\n' "${packages[@]}" 2>/dev/null | sort -u)
    readarray -t frameworks < <(printf '%s\n' "${frameworks[@]}" 2>/dev/null | sort -u)

    cat <<EOF
{
  "encontrado": true,
  "num_proyectos": $num_projects,
  "target_frameworks": $(to_json_array "${frameworks[@]+"${frameworks[@]}"}"),
  "num_paquetes": ${#packages[@]},
  "paquetes": $(to_json_array "${packages[@]:0:40}")
}
EOF
}

# =============================================================================
# SECCIÓN 3: CONFIGURACIÓN Y CONEXIONES
# =============================================================================

analizar_env_files() {
    log_progress "Config" "Analizando archivos .env..."
    local env_files
    env_files=$(safe_find "$REPO_PATH" -type f \( -name ".env" -o -name ".env.*" -o -name "*.env" \) \
        | grep -v "node_modules\|\.git\|vendor" || true)
    
    if [[ -z "$env_files" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local all_vars=()
    local env_file_list=()

    while IFS= read -r env_file; do
        [[ -z "$env_file" ]] && continue
        local rel_path="${env_file#$REPO_PATH/}"
        env_file_list+=("$rel_path")
        
        # Solo extraer NOMBRES de variables, nunca valores
        while IFS= read -r var_name; do
            [[ -n "$var_name" && ! "$var_name" =~ ^# ]] && all_vars+=("$var_name")
        done < <(safe_grep -oP '^[A-Za-z_][A-Za-z0-9_]*(?==)' "$env_file" 2>/dev/null)
    done <<< "$env_files"

    readarray -t all_vars < <(printf '%s\n' "${all_vars[@]}" 2>/dev/null | sort -u)

    cat <<EOF
{
  "encontrado": true,
  "archivos": $(to_json_array "${env_file_list[@]+"${env_file_list[@]}"}"),
  "variables_nombres": $(to_json_array "${all_vars[@]+"${all_vars[@]}"}")
}
EOF
}

analizar_spring_config() {
    log_progress "Config" "Analizando configuración Spring Boot..."
    local spring_files
    spring_files=$(safe_find "$REPO_PATH" -type f \( -name "application.yml" -o -name "application.yaml" -o -name "application.properties" -o -name "application-*.yml" -o -name "application-*.yaml" -o -name "application-*.properties" -o -name "bootstrap.yml" -o -name "bootstrap.yaml" \))
    
    if [[ -z "$spring_files" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local profiles=()
    local config_files=()
    local datasources=()
    local ports=()

    while IFS= read -r sf; do
        [[ -z "$sf" ]] && continue
        local rel_path="${sf#$REPO_PATH/}"
        config_files+=("$rel_path")
        local content
        content=$(safe_read_file "$sf") || continue
        
        # Detectar perfiles
        local profile
        profile=$(echo "$rel_path" | safe_grep -oP 'application-\K[^.]+')
        [[ -n "$profile" ]] && profiles+=("$profile")
        
        # Detectar datasource
        while IFS= read -r ds; do
            [[ -n "$ds" ]] && datasources+=("$ds")
        done < <(echo "$content" | safe_grep -oP '(url|uri)\s*[:=]\s*\K(jdbc:[a-zA-Z]+|[a-z]+://)' | sort -u)
        
        # Detectar puertos
        while IFS= read -r port; do
            [[ -n "$port" ]] && ports+=("$port")
        done < <(echo "$content" | safe_grep -oP '(server\.port|port)\s*[:=]\s*\K[0-9]+' | sort -u)
        
    done <<< "$spring_files"

    readarray -t profiles < <(printf '%s\n' "${profiles[@]}" 2>/dev/null | sort -u)

    cat <<EOF
{
  "encontrado": true,
  "archivos": $(to_json_array "${config_files[@]+"${config_files[@]}"}"),
  "profiles": $(to_json_array "${profiles[@]+"${profiles[@]}"}"),
  "datasources_tipo": $(to_json_array "${datasources[@]+"${datasources[@]}"}"),
  "puertos": $(to_json_array "${ports[@]+"${ports[@]}"}")
}
EOF
}

analizar_conexiones() {
    log_progress "Config" "Detectando patrones de conexión..."
    
    # Buscar patrones de connection strings en todo el repo
    local db_patterns=()
    local api_urls=()
    
    # Bases de datos
    local postgres_count
    postgres_count=$(safe_find "$REPO_PATH" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "*.properties" -o -name "*.env*" -o -name "*.tf" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.java" -o -name "*.rb" -o -name "*.php" -o -name "*.toml" -o -name "*.cfg" -o -name "*.conf" -o -name "*.xml" \) \
        -exec grep -l "postgres://\|postgresql://\|5432\|PostgreSQL\|pg_connection" {} \; 2>/dev/null | wc -l)
    [[ $postgres_count -gt 0 ]] && db_patterns+=("PostgreSQL ($postgres_count archivos)")
    
    local mongo_count
    mongo_count=$(safe_find "$REPO_PATH" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "*.properties" -o -name "*.env*" -o -name "*.tf" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.java" \) \
        -exec grep -l "mongodb://\|mongodb+srv://\|27017\|MongoClient" {} \; 2>/dev/null | wc -l)
    [[ $mongo_count -gt 0 ]] && db_patterns+=("MongoDB ($mongo_count archivos)")
    
    local redis_count
    redis_count=$(safe_find "$REPO_PATH" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "*.properties" -o -name "*.env*" -o -name "*.tf" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.java" \) \
        -exec grep -l "redis://\|rediss://\|6379\|RedisClient\|ioredis" {} \; 2>/dev/null | wc -l)
    [[ $redis_count -gt 0 ]] && db_patterns+=("Redis ($redis_count archivos)")
    
    local mysql_count
    mysql_count=$(safe_find "$REPO_PATH" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "*.properties" -o -name "*.env*" -o -name "*.tf" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.java" \) \
        -exec grep -l "mysql://\|3306\|MySqlConnection\|mysql2" {} \; 2>/dev/null | wc -l)
    [[ $mysql_count -gt 0 ]] && db_patterns+=("MySQL ($mysql_count archivos)")
    
    local dynamodb_count
    dynamodb_count=$(safe_find "$REPO_PATH" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "*.tf" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.java" \) \
        -exec grep -l "dynamodb\|DynamoDB\|aws_dynamodb" {} \; 2>/dev/null | wc -l)
    [[ $dynamodb_count -gt 0 ]] && db_patterns+=("DynamoDB ($dynamodb_count archivos)")
    
    local elasticsearch_count
    elasticsearch_count=$(safe_find "$REPO_PATH" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "*.properties" -o -name "*.tf" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.java" \) \
        -exec grep -l "elasticsearch\|opensearch\|9200\|elastic.co" {} \; 2>/dev/null | wc -l)
    [[ $elasticsearch_count -gt 0 ]] && db_patterns+=("Elasticsearch/OpenSearch ($elasticsearch_count archivos)")

    # URLs externas (APIs de terceros)
    local external_apis=()
    while IFS= read -r url; do
        [[ -n "$url" ]] && external_apis+=("$url")
    done < <(safe_find "$REPO_PATH" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "*.env*" -o -name "*.properties" -o -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.go" -o -name "*.java" \) \
        -exec grep -ohP 'https?://[a-zA-Z0-9._-]+\.(com|io|org|net|dev|cloud|aws|azure)[a-zA-Z0-9/._-]*' {} \; 2>/dev/null \
        | grep -v "github.com\|stackoverflow\|google.com/search\|npmjs.com\|pypi.org\|maven\|localhost\|example.com\|schema.org" \
        | sort -u | head -30)

    cat <<EOF
{
  "bases_de_datos": $(to_json_array "${db_patterns[@]+"${db_patterns[@]}"}"),
  "apis_externas": $(to_json_array "${external_apis[@]+"${external_apis[@]}"}")
}
EOF
}

# =============================================================================
# SECCIÓN 4: INDICADORES DE ARQUITECTURA
# =============================================================================

analizar_dockerfiles() {
    log_progress "Arch" "Analizando Dockerfiles..."
    local dockerfiles
    dockerfiles=$(safe_find "$REPO_PATH" -type f \( -name "Dockerfile" -o -name "Dockerfile.*" -o -name "*.Dockerfile" \))
    
    if [[ -z "$dockerfiles" ]]; then
        echo '{"encontrado": false}'
        return
    fi

    local base_images=()
    local exposed_ports=()
    local entrypoints=()
    local docker_info="["
    local first=true
    local num_files=0

    while IFS= read -r dockerfile; do
        [[ -z "$dockerfile" ]] && continue
        ((num_files++))
        local content
        content=$(safe_read_file "$dockerfile") || continue
        local rel_path="${dockerfile#$REPO_PATH/}"
        
        # Imagen base
        local images=()
        while IFS= read -r img; do
            [[ -n "$img" && "$img" != "scratch" ]] && images+=("$img") && base_images+=("$img")
        done < <(echo "$content" | safe_grep -oP '^FROM\s+\K[^\s]+' | sed 's/ AS.*//i')
        
        # Puertos
        local ports=()
        while IFS= read -r port; do
            [[ -n "$port" ]] && ports+=("$port") && exposed_ports+=("$port")
        done < <(echo "$content" | safe_grep -oP 'EXPOSE\s+\K[0-9]+')
        
        # Entrypoint/CMD
        local ep=""
        ep=$(echo "$content" | safe_grep -oP '(ENTRYPOINT|CMD)\s+\K.*' | tail -1)
        [[ -n "$ep" ]] && entrypoints+=("$rel_path: $ep")
        
        if [ "$first" = true ]; then first=false; else docker_info+=","; fi
        docker_info+="{\"path\":\"$(json_escape "$rel_path")\",\"base_images\":$(to_json_array "${images[@]+"${images[@]}"}"),\"ports\":$(to_json_array "${ports[@]+"${ports[@]}"}")}"
        
    done <<< "$dockerfiles"
    docker_info+="]"

    readarray -t base_images < <(printf '%s\n' "${base_images[@]}" 2>/dev/null | sort -u)
    readarray -t exposed_ports < <(printf '%s\n' "${exposed_ports[@]}" 2>/dev/null | sort -u)

    cat <<EOF
{
  "encontrado": true,
  "num_dockerfiles": $num_files,
  "base_images": $(to_json_array "${base_images[@]+"${base_images[@]}"}"),
  "puertos_expuestos": $(to_json_array "${exposed_ports[@]+"${exposed_ports[@]}"}"),
  "entrypoints": $(to_json_array "${entrypoints[@]+"${entrypoints[@]}"}"),
  "detalle": $docker_info
}
EOF
}

analizar_cicd() {
    log_progress "Arch" "Analizando CI/CD..."
    local cicd_info="{"
    local found_any=false
    
    # GitHub Actions
    local gh_workflows
    gh_workflows=$(safe_find "$REPO_PATH/.github/workflows" -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null)
    if [[ -n "$gh_workflows" ]]; then
        found_any=true
        local wf_names=()
        while IFS= read -r wf; do
            [[ -z "$wf" ]] && continue
            local name
            name=$(safe_grep -oP '^name:\s*\K.*' "$wf" | head -1)
            [[ -z "$name" ]] && name=$(basename "$wf" .yml)
            wf_names+=("$name")
        done <<< "$gh_workflows"
        cicd_info+="\"github_actions\": {\"encontrado\": true, \"workflows\": $(to_json_array "${wf_names[@]+"${wf_names[@]}"}")},"
    else
        cicd_info+="\"github_actions\": {\"encontrado\": false},"
    fi
    
    # GitLab CI
    local gitlab_ci="$REPO_PATH/.gitlab-ci.yml"
    if [[ -f "$gitlab_ci" ]]; then
        found_any=true
        local stages=()
        while IFS= read -r stage; do
            [[ -n "$stage" ]] && stages+=("$stage")
        done < <(safe_grep -oP '^\s+-\s+\K.*' "$gitlab_ci" | head -20)
        cicd_info+="\"gitlab_ci\": {\"encontrado\": true, \"stages\": $(to_json_array "${stages[@]+"${stages[@]}"}")},"
    else
        cicd_info+="\"gitlab_ci\": {\"encontrado\": false},"
    fi
    
    # Jenkinsfile
    local jenkinsfile
    jenkinsfile=$(safe_find "$REPO_PATH" -maxdepth 2 -name "Jenkinsfile" -type f | head -1)
    if [[ -n "$jenkinsfile" ]]; then
        found_any=true
        local content
        content=$(safe_read_file "$jenkinsfile") || content=""
        local stages=()
        while IFS= read -r stage; do
            [[ -n "$stage" ]] && stages+=("$stage")
        done < <(echo "$content" | safe_grep -oP "stage\s*\(\s*['\"]?\K[^'\")+]+" | head -20)
        cicd_info+="\"jenkins\": {\"encontrado\": true, \"stages\": $(to_json_array "${stages[@]+"${stages[@]}"}")},"
    else
        cicd_info+="\"jenkins\": {\"encontrado\": false},"
    fi
    
    # AWS CodeBuild/CodePipeline
    local buildspec
    buildspec=$(safe_find "$REPO_PATH" -maxdepth 2 -name "buildspec*.yml" -o -name "buildspec*.yaml" -type f 2>/dev/null | head -1)
    if [[ -n "$buildspec" ]]; then
        found_any=true
        cicd_info+="\"aws_codebuild\": {\"encontrado\": true, \"archivo\": \"${buildspec#$REPO_PATH/}\"},"
    else
        cicd_info+="\"aws_codebuild\": {\"encontrado\": false},"
    fi
    
    # CircleCI
    local circleci="$REPO_PATH/.circleci/config.yml"
    if [[ -f "$circleci" ]]; then
        found_any=true
        cicd_info+="\"circleci\": {\"encontrado\": true},"
    else
        cicd_info+="\"circleci\": {\"encontrado\": false},"
    fi

    # Azure Pipelines
    local azure_pipelines
    azure_pipelines=$(safe_find "$REPO_PATH" -maxdepth 1 -name "azure-pipelines*.yml" -type f | head -1)
    if [[ -n "$azure_pipelines" ]]; then
        found_any=true
        cicd_info+="\"azure_pipelines\": {\"encontrado\": true},"
    else
        cicd_info+="\"azure_pipelines\": {\"encontrado\": false},"
    fi

    cicd_info+="\"alguno_encontrado\": $found_any"
    cicd_info+="}"
    echo "$cicd_info"
}

analizar_api_definitions() {
    log_progress "Arch" "Analizando definiciones de API..."
    
    # OpenAPI/Swagger
    local openapi_files
    openapi_files=$(safe_find "$REPO_PATH" -type f \( -name "swagger*" -o -name "openapi*" -o -name "api-spec*" \) \
        | grep -iE "\.(json|yml|yaml)$" || true)
    
    # También buscar por contenido
    if [[ -z "$openapi_files" ]]; then
        openapi_files=$(safe_find "$REPO_PATH" -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" \) \
            -exec grep -l "openapi:\|swagger:" {} \; 2>/dev/null | head -5 || true)
    fi
    
    # GraphQL
    local graphql_files
    graphql_files=$(safe_find "$REPO_PATH" -type f \( -name "*.graphql" -o -name "*.gql" -o -name "schema.graphql" \) | head -20)
    
    # gRPC / Protobuf
    local proto_files
    proto_files=$(safe_find "$REPO_PATH" -type f -name "*.proto" | head -20)
    
    local proto_services=()
    if [[ -n "$proto_files" ]]; then
        while IFS= read -r pf; do
            [[ -z "$pf" ]] && continue
            while IFS= read -r svc; do
                [[ -n "$svc" ]] && proto_services+=("$svc")
            done < <(safe_grep -oP 'service\s+\K[A-Za-z0-9_]+' "$pf")
        done <<< "$proto_files"
    fi

    local openapi_count=0
    [[ -n "$openapi_files" ]] && openapi_count=$(echo "$openapi_files" | grep -c "." 2>/dev/null || echo 0)
    local graphql_count=0
    [[ -n "$graphql_files" ]] && graphql_count=$(echo "$graphql_files" | grep -c "." 2>/dev/null || echo 0)
    local proto_count=0
    [[ -n "$proto_files" ]] && proto_count=$(echo "$proto_files" | grep -c "." 2>/dev/null || echo 0)

    cat <<EOF
{
  "openapi_swagger": {"encontrado": $([ $openapi_count -gt 0 ] && echo "true" || echo "false"), "num_archivos": $openapi_count},
  "graphql": {"encontrado": $([ $graphql_count -gt 0 ] && echo "true" || echo "false"), "num_schemas": $graphql_count},
  "grpc_protobuf": {"encontrado": $([ $proto_count -gt 0 ] && echo "true" || echo "false"), "num_protos": $proto_count, "services": $(to_json_array "${proto_services[@]+"${proto_services[@]}"}")}
}
EOF
}

analizar_microservicios() {
    log_progress "Arch" "Detectando indicadores de microservicios..."
    
    local num_dockerfiles
    num_dockerfiles=$(safe_find "$REPO_PATH" -type f \( -name "Dockerfile" -o -name "Dockerfile.*" \) | wc -l)
    
    local num_package_json
    num_package_json=$(safe_find "$REPO_PATH" -name "package.json" -type f | wc -l)
    
    local num_go_mod
    num_go_mod=$(safe_find "$REPO_PATH" -name "go.mod" -type f | wc -l)
    
    local num_pom
    num_pom=$(safe_find "$REPO_PATH" -name "pom.xml" -type f | wc -l)
    
    local num_csproj
    num_csproj=$(safe_find "$REPO_PATH" -type f -name "*.csproj" | wc -l)
    
    # Determinar si es monorepo
    local es_monorepo=false
    local indicadores_monorepo=0
    [[ $num_dockerfiles -gt 2 ]] && ((indicadores_monorepo++))
    [[ $num_package_json -gt 2 ]] && ((indicadores_monorepo++))
    [[ $num_go_mod -gt 1 ]] && ((indicadores_monorepo++))
    [[ $num_pom -gt 3 ]] && ((indicadores_monorepo++))
    [[ $num_csproj -gt 2 ]] && ((indicadores_monorepo++))
    [[ -f "$REPO_PATH/lerna.json" || -f "$REPO_PATH/pnpm-workspace.yaml" || -f "$REPO_PATH/nx.json" ]] && ((indicadores_monorepo++))
    [[ $indicadores_monorepo -ge 2 ]] && es_monorepo=true
    
    # Detectar herramientas de monorepo
    local monorepo_tools=()
    [[ -f "$REPO_PATH/lerna.json" ]] && monorepo_tools+=("lerna")
    [[ -f "$REPO_PATH/pnpm-workspace.yaml" ]] && monorepo_tools+=("pnpm-workspaces")
    [[ -f "$REPO_PATH/nx.json" ]] && monorepo_tools+=("nx")
    [[ -f "$REPO_PATH/turbo.json" ]] && monorepo_tools+=("turborepo")
    safe_grep -q "workspaces" "$REPO_PATH/package.json" 2>/dev/null && monorepo_tools+=("yarn-workspaces")

    cat <<EOF
{
  "num_dockerfiles": $num_dockerfiles,
  "num_package_json": $num_package_json,
  "num_go_mod": $num_go_mod,
  "num_pom_xml": $num_pom,
  "num_csproj": $num_csproj,
  "es_monorepo": $es_monorepo,
  "herramientas_monorepo": $(to_json_array "${monorepo_tools[@]+"${monorepo_tools[@]}"}"),
  "indicadores_microservicios": $indicadores_monorepo
}
EOF
}

# =============================================================================
# SECCIÓN 5: ESTRUCTURA DEL CÓDIGO
# =============================================================================

analizar_estructura() {
    log_progress "Struct" "Analizando estructura del código..."
    
    # Árbol de directorios (3 niveles, excluyendo directorios comunes)
    local dir_tree=""
    if cmd_exists tree; then
        dir_tree=$(tree -d -L 3 -I "node_modules|.git|vendor|__pycache__|venv|.venv|dist|build|target|.terraform|.gradle|bin|obj" "$REPO_PATH" 2>/dev/null | head -100)
    else
        dir_tree=$(safe_find "$REPO_PATH" -maxdepth 3 -type d \
            | sed "s|$REPO_PATH||" | sort | head -100)
    fi
    
    # Conteo de archivos por extensión
    local file_counts=""
    file_counts=$(safe_find "$REPO_PATH" -type f -name "*.*" \
        | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -25 \
        | awk '{printf "    \"%s\": %d,\n", $2, $1}')
    # Quitar última coma
    file_counts=$(echo "$file_counts" | sed '$ s/,$//')
    
    # Total de archivos
    local total_files
    total_files=$(safe_find "$REPO_PATH" -type f | wc -l)
    
    # Total de líneas de código (aproximación rápida)
    local total_loc=0
    total_loc=$(safe_find "$REPO_PATH" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.java" -o -name "*.go" -o -name "*.rb" -o -name "*.php" -o -name "*.rs" -o -name "*.cs" -o -name "*.cpp" -o -name "*.c" -o -name "*.swift" -o -name "*.kt" \) \
        -exec wc -l {} \; 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    
    # Detectar entry points principales
    local entry_points=()
    # Node.js
    [[ -f "$REPO_PATH/index.js" ]] && entry_points+=("index.js")
    [[ -f "$REPO_PATH/index.ts" ]] && entry_points+=("index.ts")
    [[ -f "$REPO_PATH/src/index.js" ]] && entry_points+=("src/index.js")
    [[ -f "$REPO_PATH/src/index.ts" ]] && entry_points+=("src/index.ts")
    [[ -f "$REPO_PATH/src/main.ts" ]] && entry_points+=("src/main.ts")
    [[ -f "$REPO_PATH/src/app.ts" ]] && entry_points+=("src/app.ts")
    [[ -f "$REPO_PATH/server.js" ]] && entry_points+=("server.js")
    [[ -f "$REPO_PATH/app.js" ]] && entry_points+=("app.js")
    # Python
    [[ -f "$REPO_PATH/main.py" ]] && entry_points+=("main.py")
    [[ -f "$REPO_PATH/app.py" ]] && entry_points+=("app.py")
    [[ -f "$REPO_PATH/manage.py" ]] && entry_points+=("manage.py (Django)")
    [[ -f "$REPO_PATH/wsgi.py" ]] && entry_points+=("wsgi.py")
    [[ -f "$REPO_PATH/src/main.py" ]] && entry_points+=("src/main.py")
    # Java
    local java_main
    java_main=$(safe_find "$REPO_PATH" -name "*.java" -exec grep -l "public static void main" {} \; 2>/dev/null | head -3)
    if [[ -n "$java_main" ]]; then
        while IFS= read -r jm; do
            entry_points+=("${jm#$REPO_PATH/}")
        done <<< "$java_main"
    fi
    # Go
    local go_main
    go_main=$(safe_find "$REPO_PATH" -name "main.go" -type f | head -3)
    if [[ -n "$go_main" ]]; then
        while IFS= read -r gm; do
            entry_points+=("${gm#$REPO_PATH/}")
        done <<< "$go_main"
    fi
    # .NET
    [[ -f "$REPO_PATH/Program.cs" ]] && entry_points+=("Program.cs")
    local program_cs
    program_cs=$(safe_find "$REPO_PATH" -name "Program.cs" -type f | head -3)
    if [[ -n "$program_cs" ]]; then
        while IFS= read -r pc; do
            local rel="${pc#$REPO_PATH/}"
            [[ "$rel" != "Program.cs" ]] && entry_points+=("$rel")
        done <<< "$program_cs"
    fi
    # Rust
    [[ -f "$REPO_PATH/src/main.rs" ]] && entry_points+=("src/main.rs")

    # README
    local readme_content=""
    local readme_file
    readme_file=$(safe_find "$REPO_PATH" -maxdepth 1 -iname "readme*" -type f | head -1)
    if [[ -n "$readme_file" ]]; then
        readme_content=$(head -100 "$readme_file" 2>/dev/null | tr '\t' ' ')
    fi

    cat <<EOF
{
  "total_archivos": $total_files,
  "total_lineas_codigo": $total_loc,
  "archivos_por_extension": {
$file_counts
  },
  "entry_points": $(to_json_array "${entry_points[@]+"${entry_points[@]}"}"),
  "readme_preview": "$(json_escape "${readme_content:0:3000}")",
  "arbol_directorios": "$(json_escape "$dir_tree")"
}
EOF
}

analizar_git_info() {
    log_progress "Struct" "Analizando información de Git..."
    
    if [[ ! -d "$REPO_PATH/.git" ]]; then
        echo '{"encontrado": false, "razon": "No es un repositorio git"}'
        return
    fi

    # Rama actual
    local current_branch
    current_branch=$(git -C "$REPO_PATH" branch --show-current 2>/dev/null || echo "desconocida")
    
    # Todas las ramas
    local branches=()
    while IFS= read -r branch; do
        branch=$(echo "$branch" | sed 's/^[* ]*//' | tr -d '[:space:]')
        [[ -n "$branch" ]] && branches+=("$branch")
    done < <(git -C "$REPO_PATH" branch -a 2>/dev/null | head -30)
    
    # Últimos 10 commits
    local recent_commits=()
    while IFS= read -r commit; do
        [[ -n "$commit" ]] && recent_commits+=("$commit")
    done < <(git -C "$REPO_PATH" log --oneline -10 --format="%h - %s (%an, %ar)" 2>/dev/null)
    
    # Contribuidores
    local contributors=()
    while IFS= read -r contrib; do
        [[ -n "$contrib" ]] && contributors+=("$contrib")
    done < <(git -C "$REPO_PATH" shortlog -sne --all 2>/dev/null | head -20 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')
    
    # Remotes
    local remotes=()
    while IFS= read -r remote; do
        [[ -n "$remote" ]] && remotes+=("$remote")
    done < <(git -C "$REPO_PATH" remote -v 2>/dev/null | awk '{print $1 " " $2}' | sort -u)
    
    # Tags
    local tags=()
    while IFS= read -r tag; do
        [[ -n "$tag" ]] && tags+=("$tag")
    done < <(git -C "$REPO_PATH" tag --sort=-creatordate 2>/dev/null | head -10)
    
    # Primer y último commit
    local first_commit
    first_commit=$(git -C "$REPO_PATH" log --reverse --format="%ai" 2>/dev/null | head -1)
    local last_commit
    last_commit=$(git -C "$REPO_PATH" log -1 --format="%ai" 2>/dev/null)
    
    # Total de commits
    local total_commits
    total_commits=$(git -C "$REPO_PATH" rev-list --all --count 2>/dev/null || echo "0")

    cat <<EOF
{
  "encontrado": true,
  "rama_actual": "$(json_escape "$current_branch")",
  "num_ramas": ${#branches[@]},
  "ramas": $(to_json_array "${branches[@]+"${branches[@]}"}"),
  "total_commits": $total_commits,
  "primer_commit": "$(json_escape "$first_commit")",
  "ultimo_commit": "$(json_escape "$last_commit")",
  "commits_recientes": $(to_json_array "${recent_commits[@]+"${recent_commits[@]}"}"),
  "contribuidores": $(to_json_array "${contributors[@]+"${contributors[@]}"}"),
  "remotes": $(to_json_array "${remotes[@]+"${remotes[@]}"}"),
  "tags_recientes": $(to_json_array "${tags[@]+"${tags[@]}"}")
}
EOF
}

# =============================================================================
# SECCIÓN 6: PATRONES DE COMUNICACIÓN
# =============================================================================

analizar_comunicacion() {
    log_progress "Comm" "Detectando patrones de comunicación..."
    
    local code_files_pattern="-name '*.js' -o -name '*.ts' -o -name '*.py' -o -name '*.java' -o -name '*.go' -o -name '*.rb' -o -name '*.php' -o -name '*.cs' -o -name '*.rs'"
    
    # HTTP Clients
    local http_clients=()
    local axios_count
    axios_count=$(safe_find "$REPO_PATH" -type f \( -name "*.js" -o -name "*.ts" \) -exec grep -l "axios\|from ['\"]axios" {} \; 2>/dev/null | wc -l)
    [[ $axios_count -gt 0 ]] && http_clients+=("axios ($axios_count archivos)")
    
    local fetch_count
    fetch_count=$(safe_find "$REPO_PATH" -type f \( -name "*.js" -o -name "*.ts" \) -exec grep -l "fetch(\|node-fetch" {} \; 2>/dev/null | wc -l)
    [[ $fetch_count -gt 0 ]] && http_clients+=("fetch ($fetch_count archivos)")
    
    local requests_count
    requests_count=$(safe_find "$REPO_PATH" -type f -name "*.py" -exec grep -l "import requests\|from requests\|httpx\|aiohttp" {} \; 2>/dev/null | wc -l)
    [[ $requests_count -gt 0 ]] && http_clients+=("python-requests/httpx ($requests_count archivos)")
    
    local http_client_java
    http_client_java=$(safe_find "$REPO_PATH" -type f -name "*.java" -exec grep -l "HttpClient\|RestTemplate\|WebClient\|OkHttpClient\|Retrofit" {} \; 2>/dev/null | wc -l)
    [[ $http_client_java -gt 0 ]] && http_clients+=("java-http-client ($http_client_java archivos)")
    
    local http_go
    http_go=$(safe_find "$REPO_PATH" -type f -name "*.go" -exec grep -l "http.Client\|http.Get\|http.Post\|net/http" {} \; 2>/dev/null | wc -l)
    [[ $http_go -gt 0 ]] && http_clients+=("go-net-http ($http_go archivos)")
    
    # Message Queues
    local mq_patterns=()
    local rabbitmq_count
    rabbitmq_count=$(safe_find "$REPO_PATH" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.java" -o -name "*.go" -o -name "*.yml" -o -name "*.yaml" \) \
        -exec grep -l "amqp://\|amqplib\|RabbitMQ\|rabbitmq\|pika\|spring.rabbitmq" {} \; 2>/dev/null | wc -l)
    [[ $rabbitmq_count -gt 0 ]] && mq_patterns+=("RabbitMQ/AMQP ($rabbitmq_count archivos)")
    
    local kafka_count
    kafka_count=$(safe_find "$REPO_PATH" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.java" -o -name "*.go" -o -name "*.yml" -o -name "*.yaml" \) \
        -exec grep -l "kafka\|KafkaProducer\|KafkaConsumer\|kafkajs\|confluent" {} \; 2>/dev/null | wc -l)
    [[ $kafka_count -gt 0 ]] && mq_patterns+=("Kafka ($kafka_count archivos)")
    
    local sqs_count
    sqs_count=$(safe_find "$REPO_PATH" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.java" -o -name "*.go" -o -name "*.tf" -o -name "*.yml" \) \
        -exec grep -l "SQS\|sqs\|aws_sqs\|SendMessage\|ReceiveMessage" {} \; 2>/dev/null | wc -l)
    [[ $sqs_count -gt 0 ]] && mq_patterns+=("AWS SQS ($sqs_count archivos)")
    
    local sns_count
    sns_count=$(safe_find "$REPO_PATH" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.java" -o -name "*.go" -o -name "*.tf" -o -name "*.yml" \) \
        -exec grep -l "SNS\|sns\|aws_sns\|TopicArn\|publish" {} \; 2>/dev/null | wc -l)
    [[ $sns_count -gt 0 ]] && mq_patterns+=("AWS SNS ($sns_count archivos)")
    
    local redis_pubsub
    redis_pubsub=$(safe_find "$REPO_PATH" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.java" -o -name "*.go" \) \
        -exec grep -l "subscribe\|publish\|pub/sub\|pubsub\|redis.*channel" {} \; 2>/dev/null | wc -l)
    [[ $redis_pubsub -gt 0 ]] && mq_patterns+=("Redis Pub/Sub ($redis_pubsub archivos)")
    
    # gRPC
    local grpc_usage=()
    local grpc_count
    grpc_count=$(safe_find "$REPO_PATH" -type f \( -name "*.proto" -o -name "*_grpc*" -o -name "*grpc*" \) | wc -l)
    [[ $grpc_count -gt 0 ]] && grpc_usage+=("gRPC ($grpc_count archivos)")
    
    # WebSocket
    local ws_patterns=()
    local ws_count
    ws_count=$(safe_find "$REPO_PATH" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.java" -o -name "*.go" \) \
        -exec grep -l "WebSocket\|websocket\|socket.io\|ws://\|wss://\|gorilla/websocket\|socketio" {} \; 2>/dev/null | wc -l)
    [[ $ws_count -gt 0 ]] && ws_patterns+=("WebSocket ($ws_count archivos)")
    
    # Event-driven
    local event_patterns=()
    local eventbridge_count
    eventbridge_count=$(safe_find "$REPO_PATH" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.java" -o -name "*.go" -o -name "*.tf" -o -name "*.yml" \) \
        -exec grep -l "EventBridge\|eventbridge\|PutEvents\|aws_cloudwatch_event\|EventBus" {} \; 2>/dev/null | wc -l)
    [[ $eventbridge_count -gt 0 ]] && event_patterns+=("AWS EventBridge ($eventbridge_count archivos)")
    
    local lambda_count
    lambda_count=$(safe_find "$REPO_PATH" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.java" -o -name "*.go" -o -name "*.tf" -o -name "*.yml" \) \
        -exec grep -l "aws_lambda\|Lambda\|lambda_handler\|serverless\|sam\|handler.*event.*context" {} \; 2>/dev/null | wc -l)
    [[ $lambda_count -gt 0 ]] && event_patterns+=("AWS Lambda/Serverless ($lambda_count archivos)")
    
    local step_functions
    step_functions=$(safe_find "$REPO_PATH" -type f \( -name "*.tf" -o -name "*.yml" -o -name "*.yaml" -o -name "*.json" \) \
        -exec grep -l "stepfunctions\|StepFunctions\|state_machine\|StateMachine" {} \; 2>/dev/null | wc -l)
    [[ $step_functions -gt 0 ]] && event_patterns+=("AWS Step Functions ($step_functions archivos)")

    cat <<EOF
{
  "http_clients": $(to_json_array "${http_clients[@]+"${http_clients[@]}"}"),
  "message_queues": $(to_json_array "${mq_patterns[@]+"${mq_patterns[@]}"}"),
  "grpc": $(to_json_array "${grpc_usage[@]+"${grpc_usage[@]}"}"),
  "websocket": $(to_json_array "${ws_patterns[@]+"${ws_patterns[@]}"}"),
  "event_driven": $(to_json_array "${event_patterns[@]+"${event_patterns[@]}"}")
}
EOF
}

# =============================================================================
# EJECUCIÓN PRINCIPAL - ORQUESTACIÓN
# =============================================================================

main() {
    local start_time
    start_time=$(date +%s)
    
    echo -e "${BLUE}Iniciando análisis completo del repositorio...${NC}"
    echo ""

    # --- Infraestructura como Código ---
    log_progress "FASE 1/6" "Infraestructura como Código"
    local terraform_json
    terraform_json=$(analizar_terraform)
    local cloudformation_json
    cloudformation_json=$(analizar_cloudformation)
    local kubernetes_json
    kubernetes_json=$(analizar_kubernetes)
    local docker_compose_json
    docker_compose_json=$(analizar_docker_compose)
    local helm_json
    helm_json=$(analizar_helm)
    local ansible_json
    ansible_json=$(analizar_ansible)
    local pulumi_json
    pulumi_json=$(analizar_pulumi)

    # --- Dependencias de Aplicación ---
    log_progress "FASE 2/6" "Dependencias de Aplicación"
    local nodejs_json
    nodejs_json=$(analizar_nodejs)
    local python_json
    python_json=$(analizar_python)
    local java_json
    java_json=$(analizar_java)
    local go_json
    go_json=$(analizar_go)
    local ruby_json
    ruby_json=$(analizar_ruby)
    local php_json
    php_json=$(analizar_php)
    local rust_json
    rust_json=$(analizar_rust)
    local dotnet_json
    dotnet_json=$(analizar_dotnet)

    # --- Configuración y Conexiones ---
    log_progress "FASE 3/6" "Configuración y Conexiones"
    local env_json
    env_json=$(analizar_env_files)
    local spring_json
    spring_json=$(analizar_spring_config)
    local conexiones_json
    conexiones_json=$(analizar_conexiones)

    # --- Indicadores de Arquitectura ---
    log_progress "FASE 4/6" "Indicadores de Arquitectura"
    local docker_json
    docker_json=$(analizar_dockerfiles)
    local cicd_json
    cicd_json=$(analizar_cicd)
    local api_json
    api_json=$(analizar_api_definitions)
    local microservicios_json
    microservicios_json=$(analizar_microservicios)

    # --- Estructura del Código ---
    log_progress "FASE 5/6" "Estructura del Código"
    local estructura_json
    estructura_json=$(analizar_estructura)
    local git_json
    git_json=$(analizar_git_info)

    # --- Patrones de Comunicación ---
    log_progress "FASE 6/6" "Patrones de Comunicación"
    local comunicacion_json
    comunicacion_json=$(analizar_comunicacion)

    # ==========================================================================
    # GENERAR JSON FINAL
    # ==========================================================================
    log_progress "OUTPUT" "Generando archivo JSON de salida..."

    cat > "$TMP_DIR/output.json" <<FINAL_JSON
{
  "metadata": {
    "version_script": "$VERSION",
    "timestamp_analisis": "$TIMESTAMP",
    "ruta_repositorio": "$(json_escape "$REPO_PATH")",
    "nombre_repositorio": "$(json_escape "$(basename "$REPO_PATH")")"
  },
  "infraestructura_como_codigo": {
    "terraform": $terraform_json,
    "cloudformation": $cloudformation_json,
    "kubernetes": $kubernetes_json,
    "docker_compose": $docker_compose_json,
    "helm": $helm_json,
    "ansible": $ansible_json,
    "pulumi": $pulumi_json
  },
  "dependencias_aplicacion": {
    "nodejs": $nodejs_json,
    "python": $python_json,
    "java": $java_json,
    "go": $go_json,
    "ruby": $ruby_json,
    "php": $php_json,
    "rust": $rust_json,
    "dotnet": $dotnet_json
  },
  "configuracion_conexiones": {
    "env_files": $env_json,
    "spring_boot": $spring_json,
    "conexiones": $conexiones_json
  },
  "indicadores_arquitectura": {
    "dockerfiles": $docker_json,
    "cicd": $cicd_json,
    "api_definitions": $api_json,
    "microservicios": $microservicios_json
  },
  "estructura_codigo": $estructura_json,
  "git_info": $git_json,
  "patrones_comunicacion": $comunicacion_json
}
FINAL_JSON

    # Formatear con jq si está disponible
    if [[ "$HAS_JQ" == true ]]; then
        jq '.' "$TMP_DIR/output.json" > "$OUTPUT_FILE" 2>/dev/null || cp "$TMP_DIR/output.json" "$OUTPUT_FILE"
    else
        cp "$TMP_DIR/output.json" "$OUTPUT_FILE"
    fi

    # ==========================================================================
    # RESUMEN FINAL
    # ==========================================================================
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✓ ANÁLISIS COMPLETADO${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "  Duración:    ${CYAN}${duration}s${NC}"
    echo -e "  Salida:      ${CYAN}$OUTPUT_FILE${NC}"
    
    if [[ "$HAS_JQ" == true ]]; then
        local file_size
        file_size=$(du -h "$OUTPUT_FILE" | cut -f1)
        echo -e "  Tamaño:      ${CYAN}$file_size${NC}"
    fi
    
    echo ""
    echo -e "  ${YELLOW}Resumen de hallazgos:${NC}"
    
    # Mostrar qué se encontró
    local iac_found=()
    echo "$terraform_json" | grep -q '"encontrado": true' && iac_found+=("Terraform")
    echo "$cloudformation_json" | grep -q '"encontrado": true' && iac_found+=("CloudFormation")
    echo "$kubernetes_json" | grep -q '"encontrado": true' && iac_found+=("Kubernetes")
    echo "$docker_compose_json" | grep -q '"encontrado": true' && iac_found+=("Docker Compose")
    echo "$helm_json" | grep -q '"encontrado": true' && iac_found+=("Helm")
    echo "$ansible_json" | grep -q '"encontrado": true' && iac_found+=("Ansible")
    echo "$pulumi_json" | grep -q '"encontrado": true' && iac_found+=("Pulumi")
    
    if [[ ${#iac_found[@]} -gt 0 ]]; then
        echo -e "  ${GREEN}IaC:${NC} ${iac_found[*]}"
    else
        echo -e "  ${YELLOW}IaC:${NC} No detectado"
    fi
    
    local langs_found=()
    echo "$nodejs_json" | grep -q '"encontrado": true' && langs_found+=("Node.js")
    echo "$python_json" | grep -q '"encontrado": true' && langs_found+=("Python")
    echo "$java_json" | grep -q '"encontrado": true' && langs_found+=("Java")
    echo "$go_json" | grep -q '"encontrado": true' && langs_found+=("Go")
    echo "$ruby_json" | grep -q '"encontrado": true' && langs_found+=("Ruby")
    echo "$php_json" | grep -q '"encontrado": true' && langs_found+=("PHP")
    echo "$rust_json" | grep -q '"encontrado": true' && langs_found+=("Rust")
    echo "$dotnet_json" | grep -q '"encontrado": true' && langs_found+=(".NET")
    
    if [[ ${#langs_found[@]} -gt 0 ]]; then
        echo -e "  ${GREEN}Lenguajes:${NC} ${langs_found[*]}"
    fi
    
    echo "$docker_json" | grep -q '"encontrado": true' && echo -e "  ${GREEN}Docker:${NC} Sí ($(echo "$docker_json" | grep -oP '"num_dockerfiles":\s*\K[0-9]+') Dockerfiles)"
    echo "$cicd_json" | grep -q '"alguno_encontrado": true' && echo -e "  ${GREEN}CI/CD:${NC} Detectado"
    echo "$microservicios_json" | grep -q '"es_monorepo": true' && echo -e "  ${GREEN}Monorepo:${NC} Sí"
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Ejecutar
main
