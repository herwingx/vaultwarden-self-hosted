#!/bin/bash

# =============================================================================
# START - Inicia Vaultwarden con secretos descifrados
# =============================================================================
# Descifra .env.age a .env temporal, levanta Docker Compose,
# y luego elimina el archivo .env por seguridad.
#
# Uso:
#   ./start.sh              # Modo normal
#   ./start.sh --daemon     # Solo levanta (para systemd)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="$PROJECT_DIR/.env.age"
ENV_FILE="$PROJECT_DIR/.env"

# Ubicaciones de clave AGE
AGE_KEY_LOCATIONS=(
    "${AGE_KEY_FILE:-}"
    "$PROJECT_DIR/.age-key"
    "$HOME/.age/vaultwarden.key"
    "/root/.age/vaultwarden.key"
)

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Buscar clave AGE
find_age_key() {
    for key_path in "${AGE_KEY_LOCATIONS[@]}"; do
        if [[ -n "$key_path" && -f "$key_path" ]]; then
            echo "$key_path"
            return 0
        fi
    done
    return 1
}

# Verificar dependencias
check_deps() {
    if ! command -v age &> /dev/null; then
        log_error "age no está instalado"
        echo "  Instalar con: dnf install age / apt install age"
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        log_error "docker no está instalado"
        exit 1
    fi
}

# Descifrar secretos a .env
decrypt_to_env() {
    if [[ ! -f "$SECRETS_FILE" ]]; then
        log_error "No existe $SECRETS_FILE"
        echo "  Ejecuta: ./manage_secrets.sh encrypt"
        exit 1
    fi
    
    log_info "Descifrando secretos..."
    
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    if [[ -n "$AGE_KEY" ]]; then
        # Modo identity key (recomendado)
        log_info "Usando clave: $AGE_KEY"
        age -d -i "$AGE_KEY" -o "$ENV_FILE" "$SECRETS_FILE"
    elif [[ -n "${AGE_PASSPHRASE:-}" ]]; then
        # Modo passphrase automático
        echo "$AGE_PASSPHRASE" | age -d -o "$ENV_FILE" "$SECRETS_FILE"
    else
        # Modo interactivo
        age -d -o "$ENV_FILE" "$SECRETS_FILE"
    fi
    
    log_success "Secretos descifrados a .env"
}

# Limpiar .env
cleanup() {
    if [[ -f "$ENV_FILE" ]]; then
        rm -f "$ENV_FILE"
        log_info "Archivo .env eliminado"
    fi
}

# Main
main() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  🔐 VAULTWARDEN - Inicio Seguro"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    check_deps
    
    # Limpiar al salir (Ctrl+C, error, etc)
    trap cleanup EXIT
    
    decrypt_to_env
    
    log_info "Levantando servicios..."
    cd "$PROJECT_DIR"
    
    docker compose up -d
    
    log_success "Servicios iniciados"
    echo ""
    
    # Mostrar estado
    docker compose ps
    
    echo ""
    log_success "Vaultwarden está corriendo"
    
    # El .env se elimina automáticamente al salir (trap)
}

main "$@"
