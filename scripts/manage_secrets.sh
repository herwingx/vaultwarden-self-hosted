#!/bin/bash

# =============================================================================
# MANAGE SECRETS - Gestor de secretos cifrados con AGE
# =============================================================================
# Soporta dos modos de cifrado:
#   1. IDENTITY KEY (recomendado): Cifrado con par de claves pública/privada
#   2. PASSPHRASE: Cifrado con contraseña (requiere terminal para descifrar)
#
# Uso:
#   ./manage_secrets.sh setup      - Genera par de claves AGE
#   ./manage_secrets.sh encrypt    - Cifra .env -> .env.age
#   ./manage_secrets.sh decrypt    - Descifra .env.age -> .env
#   ./manage_secrets.sh edit       - Edita .env.age (descifra, edita, re-cifra)
#   ./manage_secrets.sh view       - Muestra el contenido cifrado (sin guardar)
#   ./manage_secrets.sh show-key   - Muestra la clave para respaldar
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="$PROJECT_DIR/.env"
ENCRYPTED_FILE="$PROJECT_DIR/.env.age"

# Ubicaciones de clave AGE (en orden de prioridad)
AGE_KEY_LOCATIONS=(
    "${AGE_KEY_FILE:-}"                          # Variable de entorno
    "$PROJECT_DIR/.age-key"                       # En el proyecto (gitignored)
    "$HOME/.age/vaultwarden.key"                  # Usuario normal
    "/root/.age/vaultwarden.key"                  # Root
)

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Verificar que age está instalado
check_age() {
    if ! command -v age &> /dev/null; then
        log_error "age no está instalado."
        echo "  Instalar con:"
        echo "    dnf install age     # Fedora"
        echo "    apt install age     # Ubuntu/Debian"
        exit 1
    fi
}

# Buscar clave AGE existente
find_age_key() {
    for key_path in "${AGE_KEY_LOCATIONS[@]}"; do
        if [[ -n "$key_path" && -f "$key_path" ]]; then
            echo "$key_path"
            return 0
        fi
    done
    return 1
}

# Obtener clave pública desde archivo de identidad
get_public_key() {
    local key_file="$1"
    age-keygen -y "$key_file" 2>/dev/null
}

# Setup: Generar par de claves
setup_keys() {
    check_age
    
    local KEY_DIR="$HOME/.age"
    local KEY_FILE="$KEY_DIR/vaultwarden.key"
    
    if [[ -f "$KEY_FILE" ]]; then
        log_warning "Ya existe una clave en: $KEY_FILE"
        read -p "¿Sobrescribir? [s/N]: " -r response
        if [[ ! "$response" =~ ^[Ss]$ ]]; then
            log_info "Operación cancelada."
            exit 0
        fi
    fi
    
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"
    
    log_info "Generando par de claves AGE..."
    age-keygen -o "$KEY_FILE" 2>&1
    chmod 600 "$KEY_FILE"
    
    echo ""
    log_success "Clave generada en: $KEY_FILE"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}⚠ IMPORTANTE: Guarda esta clave en un lugar seguro (Bitwarden)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    cat "$KEY_FILE"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    log_info "Clave pública (para compartir): $(get_public_key "$KEY_FILE")"
    echo ""
}

# Mostrar clave para respaldar
show_key() {
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    if [[ -z "$AGE_KEY" ]]; then
        log_error "No se encontró ninguna clave AGE"
        echo "  Ejecuta: ./manage_secrets.sh setup"
        exit 1
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}🔐 CLAVE AGE - GUARDA ESTO EN BITWARDEN${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Ubicación: $AGE_KEY"
    echo ""
    cat "$AGE_KEY"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Para recuperar en otro servidor:"
    echo "  1. mkdir -p ~/.age && chmod 700 ~/.age"
    echo "  2. nano ~/.age/vaultwarden.key  # Pegar el contenido"
    echo "  3. chmod 600 ~/.age/vaultwarden.key"
    echo ""
}

# Cifrar .env -> .env.age
encrypt_secrets() {
    check_age
    
    if [[ ! -f "$SECRETS_FILE" ]]; then
        log_error "No existe $SECRETS_FILE"
        echo "  Copia secrets.env.example a .env y rellena los valores."
        exit 1
    fi
    
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    if [[ -n "$AGE_KEY" ]]; then
        # Modo IDENTITY KEY
        local PUB_KEY
        PUB_KEY=$(get_public_key "$AGE_KEY")
        
        log_info "Cifrando con identity key..."
        log_info "Clave: $AGE_KEY"
        
        if age -r "$PUB_KEY" -o "$ENCRYPTED_FILE" "$SECRETS_FILE"; then
            log_success "Archivo cifrado: $ENCRYPTED_FILE"
        else
            log_error "Error al cifrar."
            exit 1
        fi
    else
        # Modo PASSPHRASE
        log_warning "No se encontró identity key, usando passphrase..."
        log_warning "Nota: El modo passphrase NO funciona con cron automático"
        echo ""
        
        if age -p -o "$ENCRYPTED_FILE" "$SECRETS_FILE"; then
            log_success "Archivo cifrado: $ENCRYPTED_FILE"
        else
            log_error "Error al cifrar."
            exit 1
        fi
    fi
    
    # Preguntar si eliminar el archivo plano
    echo ""
    read -p "¿Eliminar .env (archivo plano)? [S/n]: " -r response
    response=${response:-S}
    if [[ "$response" =~ ^[Ss]$ ]]; then
        rm "$SECRETS_FILE"
        log_success "Archivo plano eliminado."
    else
        log_warning "El archivo plano NO fue eliminado. ¡Recuerda borrarlo!"
    fi
}

# Descifrar .env.age -> .env
decrypt_secrets() {
    check_age
    
    if [[ ! -f "$ENCRYPTED_FILE" ]]; then
        log_error "No existe $ENCRYPTED_FILE"
        exit 1
    fi
    
    if [[ -f "$SECRETS_FILE" ]]; then
        log_warning "Ya existe $SECRETS_FILE"
        read -p "¿Sobrescribir? [s/N]: " -r response
        if [[ ! "$response" =~ ^[Ss]$ ]]; then
            log_info "Operación cancelada."
            exit 0
        fi
    fi
    
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    log_info "Descifrando $ENCRYPTED_FILE..."
    
    if [[ -n "$AGE_KEY" ]]; then
        log_info "Usando identity key: $AGE_KEY"
        if age -d -i "$AGE_KEY" -o "$SECRETS_FILE" "$ENCRYPTED_FILE"; then
            log_success "Archivo descifrado: $SECRETS_FILE"
        else
            log_error "Error al descifrar."
            exit 1
        fi
    else
        log_info "Usando passphrase..."
        echo ""
        if age -d -o "$SECRETS_FILE" "$ENCRYPTED_FILE"; then
            log_success "Archivo descifrado: $SECRETS_FILE"
        else
            log_error "Error al descifrar. ¿Contraseña incorrecta?"
            exit 1
        fi
    fi
    
    log_warning "¡Recuerda eliminar .env después de usarlo!"
}

# Ver contenido sin guardar
view_secrets() {
    check_age
    
    if [[ ! -f "$ENCRYPTED_FILE" ]]; then
        log_error "No existe $ENCRYPTED_FILE"
        exit 1
    fi
    
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    log_info "Mostrando contenido de $ENCRYPTED_FILE..."
    echo ""
    echo "─────────────────────────────────────────"
    
    if [[ -n "$AGE_KEY" ]]; then
        age -d -i "$AGE_KEY" "$ENCRYPTED_FILE"
    else
        age -d "$ENCRYPTED_FILE"
    fi
    
    echo ""
    echo "─────────────────────────────────────────"
}

# Editar y re-cifrar
edit_secrets() {
    check_age
    
    if [[ ! -f "$ENCRYPTED_FILE" ]]; then
        log_error "No existe $ENCRYPTED_FILE"
        echo "  Primero crea .env y usa './manage_secrets.sh encrypt'"
        exit 1
    fi
    
    local TEMP_FILE
    TEMP_FILE=$(mktemp)
    trap "rm -f $TEMP_FILE" EXIT
    
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    log_info "Descifrando para editar..."
    
    if [[ -n "$AGE_KEY" ]]; then
        if ! age -d -i "$AGE_KEY" -o "$TEMP_FILE" "$ENCRYPTED_FILE"; then
            log_error "Error al descifrar."
            exit 1
        fi
    else
        echo ""
        if ! age -d -o "$TEMP_FILE" "$ENCRYPTED_FILE"; then
            log_error "Error al descifrar."
            exit 1
        fi
    fi
    
    # Abrir editor
    ${EDITOR:-nano} "$TEMP_FILE"
    
    echo ""
    log_info "Re-cifrando..."
    
    if [[ -n "$AGE_KEY" ]]; then
        local PUB_KEY
        PUB_KEY=$(get_public_key "$AGE_KEY")
        
        if age -r "$PUB_KEY" -o "$ENCRYPTED_FILE" "$TEMP_FILE"; then
            log_success "Secretos actualizados y re-cifrados."
        else
            log_error "Error al re-cifrar."
            exit 1
        fi
    else
        log_info "Ingresa nueva passphrase..."
        echo ""
        if age -p -o "$ENCRYPTED_FILE" "$TEMP_FILE"; then
            log_success "Secretos actualizados y re-cifrados."
        else
            log_error "Error al re-cifrar."
            exit 1
        fi
    fi
}

# Mostrar ayuda
show_help() {
    echo ""
    echo "Uso: $0 <comando>"
    echo ""
    echo "Comandos:"
    echo "  setup      Genera par de claves AGE (primera vez)"
    echo "  encrypt    Cifra .env -> .env.age"
    echo "  decrypt    Descifra .env.age -> .env"
    echo "  edit       Edita .env.age (descifra, edita, re-cifra)"
    echo "  view       Muestra el contenido cifrado sin guardar"
    echo "  show-key   Muestra la clave para respaldar en Bitwarden"
    echo ""
    echo "Flujo inicial:"
    echo "  1. ./manage_secrets.sh setup       # Generar clave"
    echo "  2. Guardar clave en Bitwarden      # ¡IMPORTANTE!"
    echo "  3. cp secrets.env.example .env     # Crear archivo"
    echo "  4. nano .env                       # Rellenar valores"
    echo "  5. ./manage_secrets.sh encrypt     # Cifrar"
    echo ""
}

# Main
case "${1:-help}" in
    setup)
        setup_keys
        ;;
    encrypt)
        encrypt_secrets
        ;;
    decrypt)
        decrypt_secrets
        ;;
    edit)
        edit_secrets
        ;;
    view)
        view_secrets
        ;;
    show-key)
        show_key
        ;;
    *)
        show_help
        ;;
esac
