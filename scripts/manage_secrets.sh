#!/bin/bash

# =============================================================================
# 🔐 THE VAULT - SECRET MANAGER (AGE)
# =============================================================================
# Suite de cifrado profesional para Vaultwarden.
# =============================================================================

set -euo pipefail

# --- CONFIGURACIÓN DE COLORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- BANNER ---
show_banner() {
    echo -e "${MAGENTA}"
    echo "    █▀▀ █▄░█ █▀▀ █▀█ █▄█ █▀█ ▀█▀"
    echo "    ██▄ █░▀█ █▄▄ █▀▄ ░█░ █▀▀ ░█░"
    echo -e "${NC}"
}

# --- FUNCIONES DE LOGGING ---
log_section() { echo -e "\n${BOLD}${CYAN}◈ $1${NC}\n" ; }
log_info()    { echo -e "  ${BLUE}ℹ${NC} $1" ; }
log_success() { echo -e "  ${GREEN}✔${NC} $1" ; }
log_warning() { echo -e "  ${YELLOW}⚠${NC} $1" ; }
log_error()   { echo -e "  ${RED}✖${NC} $1" ; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="$PROJECT_DIR/.env"
ENCRYPTED_FILE="$PROJECT_DIR/.env.age"

# Ubicaciones de clave AGE
AGE_KEY_LOCATIONS=(
    "${AGE_KEY_FILE:-}"
    "$PROJECT_DIR/.age-key"
    "$HOME/.age/vaultwarden.key"
    "/root/.age/vaultwarden.key"
)

# Verificar herramientas
check_age() {
    if ! command -v age &> /dev/null; then
        log_error "AGE no está instalado."
        exit 1
    fi
}

# Buscar clave
find_age_key() {
    for key_path in "${AGE_KEY_LOCATIONS[@]}"; do
        if [[ -n "$key_path" && -f "$key_path" ]]; then
            echo "$key_path"
            return 0
        fi
    done
    return 1
}

get_public_key() {
    local key_file="$1"
    age-keygen -y "$key_file" 2>/dev/null
}

# --- COMANDOS ---

setup_keys() {
    show_banner
    log_section "GENERACIÓN DE CLAVE MAESTRA"
    
    local KEY_DIR="$HOME/.age"
    local KEY_FILE="$KEY_DIR/vaultwarden.key"
    
    if [[ -f "$KEY_FILE" ]]; then
        log_warning "Ya existe una clave activa en: $KEY_FILE"
        read -p "    ¿Deseas sobrescribirla? [s/N]: " -r response
        if [[ ! "$response" =~ ^[Ss]$ ]]; then exit 0 ; fi
    fi
    
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"
    age-keygen -o "$KEY_FILE" 2>/dev/null
    chmod 600 "$KEY_FILE"
    
    log_success "Nueva identidad criptográfica generada."
    show_key
}

show_key() {
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    if [[ -z "$AGE_KEY" ]]; then
        log_error "No se encontró una clave privada."
        exit 1
    fi
    
    echo -e "\n${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}${BOLD}║  CLAVE PRIVADA (RESPALDO CRÍTICO)                           ║${NC}"
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    cat "$AGE_KEY"
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    log_info "Guarda esto en un lugar seguro (Bitwarden Cloud, Password Manager)."
}

encrypt_secrets() {
    check_age
    log_section "CIFRADO DE SECRETOS"
    
    if [[ ! -f "$SECRETS_FILE" ]]; then
        log_error "Archivo ${CYAN}.env${NC} no encontrado."
        exit 1
    fi
    
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    if [[ -n "$AGE_KEY" ]]; then
        local PUB_KEY
        PUB_KEY=$(get_public_key "$AGE_KEY")
        log_info "Usando llave: $AGE_KEY"
        if age -r "$PUB_KEY" -o "$ENCRYPTED_FILE" "$SECRETS_FILE"; then
            log_success "Archivo cifrado con éxito: ${GREEN}.env.age${NC}"
            echo ""
            read -p "    ¿Eliminar archivo en texto plano (.env)? [S/n]: " -r response
            response=${response:-S}
            if [[ "$response" =~ ^[Ss]$ ]]; then
                rm "$SECRETS_FILE"
                log_success "Archivo plano eliminado por seguridad."
            fi
        fi
    else
        log_error "Se requiere una IDENTITY KEY para continuar."
        exit 1
    fi
}

decrypt_secrets() {
    check_age
    log_section "DESCIFRADO DE CONFIGURACIÓN"
    
    if [[ ! -f "$ENCRYPTED_FILE" ]]; then
        log_error "No existe el archivo ${RED}.env.age${NC}"
        exit 1
    fi
    
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    if [[ -n "$AGE_KEY" ]]; then
        if age -d -i "$AGE_KEY" -o "$SECRETS_FILE" "$ENCRYPTED_FILE"; then
            log_success "Configuración restaurada en ${BOLD}.env${NC}"
        fi
    else
        log_error "Identity key no encontrada."
        exit 1
    fi
}

edit_secrets() {
    check_age
    local TEMP_FILE
    TEMP_FILE=$(mktemp)
    trap "rm -f $TEMP_FILE" EXIT
    
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    if [[ -n "$AGE_KEY" ]]; then
        age -d -i "$AGE_KEY" -o "$TEMP_FILE" "$ENCRYPTED_FILE"
        ${EDITOR:-nano} "$TEMP_FILE"
        local PUB_KEY
        PUB_KEY=$(get_public_key "$AGE_KEY")
        age -r "$PUB_KEY" -o "$ENCRYPTED_FILE" "$TEMP_FILE"
        log_success "Cambios aplicados y re-cifrados."
    else
        log_error "No se puede editar sin clave de identidad."
    fi
}

# --- MAIN ---
case "${1:-}" in
    setup)    setup_keys ;;
    encrypt)  encrypt_secrets ;;
    decrypt)  decrypt_secrets ;;
    edit)     edit_secrets ;;
    show-key) show_key ;;
    *)
        show_banner
        echo "Uso: $0 [comando]"
        echo "  setup      Generar llaves Master"
        echo "  encrypt    Proteger .env -> .env.age"
        echo "  decrypt    Restaurar .env.age -> .env"
        echo "  edit       Modificar secretos de forma segura"
        echo "  show-key   Mostrar llave para backup"
        exit 1
        ;;
esac
