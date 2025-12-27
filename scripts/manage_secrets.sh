#!/bin/bash

# =============================================================================
# MANAGE SECRETS - Gestor de secretos cifrados con AGE
# =============================================================================
# Uso:
#   ./manage_secrets.sh encrypt    - Cifra secrets.env -> secrets.env.age
#   ./manage_secrets.sh decrypt    - Descifra secrets.env.age -> secrets.env
#   ./manage_secrets.sh edit       - Edita secrets.env.age (descifra, edita, re-cifra)
#   ./manage_secrets.sh view       - Muestra el contenido cifrado (sin guardar)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="$PROJECT_DIR/.env"
ENCRYPTED_FILE="$PROJECT_DIR/.env.age"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Verificar que age está instalado
check_age() {
    if ! command -v age &> /dev/null; then
        log_error "age no está instalado."
        echo "  Instalar con: apt install age"
        exit 1
    fi
}

# Cifrar secrets.env -> secrets.env.age
encrypt_secrets() {
    check_age
    
    if [[ ! -f "$SECRETS_FILE" ]]; then
        log_error "No existe $SECRETS_FILE"
        echo "  Copia secrets.env.example a secrets.env y rellena los valores."
        exit 1
    fi
    
    log_info "Cifrando $SECRETS_FILE con passphrase..."
    echo ""
    
    if age -p -o "$ENCRYPTED_FILE" "$SECRETS_FILE"; then
        log_success "Archivo cifrado: $ENCRYPTED_FILE"
        
        # Preguntar si eliminar el archivo plano
        echo ""
        read -p "¿Eliminar secrets.env (archivo plano)? [S/n]: " -r response
        response=${response:-S}
        if [[ "$response" =~ ^[Ss]$ ]]; then
            rm "$SECRETS_FILE"
            log_success "Archivo plano eliminado."
        else
            log_warning "El archivo plano NO fue eliminado. ¡Recuerda borrarlo manualmente!"
        fi
    else
        log_error "Error al cifrar el archivo."
        exit 1
    fi
}

# Descifrar secrets.env.age -> secrets.env
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
    
    log_info "Descifrando $ENCRYPTED_FILE..."
    echo ""
    
    if age -d -o "$SECRETS_FILE" "$ENCRYPTED_FILE"; then
        log_success "Archivo descifrado: $SECRETS_FILE"
        log_warning "¡Recuerda eliminar secrets.env después de usarlo!"
    else
        log_error "Error al descifrar. ¿Contraseña incorrecta?"
        exit 1
    fi
}

# Ver contenido sin guardar
view_secrets() {
    check_age
    
    if [[ ! -f "$ENCRYPTED_FILE" ]]; then
        log_error "No existe $ENCRYPTED_FILE"
        exit 1
    fi
    
    log_info "Mostrando contenido de $ENCRYPTED_FILE..."
    echo ""
    echo "─────────────────────────────────────────"
    age -d "$ENCRYPTED_FILE"
    echo ""
    echo "─────────────────────────────────────────"
}

# Editar y re-cifrar
edit_secrets() {
    check_age
    
    if [[ ! -f "$ENCRYPTED_FILE" ]]; then
        log_error "No existe $ENCRYPTED_FILE"
        echo "  Primero crea secrets.env y usa './manage_secrets.sh encrypt'"
        exit 1
    fi
    
    local TEMP_FILE
    TEMP_FILE=$(mktemp)
    trap "rm -f $TEMP_FILE" EXIT
    
    log_info "Descifrando para editar..."
    echo ""
    
    if ! age -d -o "$TEMP_FILE" "$ENCRYPTED_FILE"; then
        log_error "Error al descifrar."
        exit 1
    fi
    
    # Abrir editor
    ${EDITOR:-nano} "$TEMP_FILE"
    
    echo ""
    log_info "Re-cifrando con nueva passphrase..."
    echo ""
    
    if age -p -o "$ENCRYPTED_FILE" "$TEMP_FILE"; then
        log_success "Secretos actualizados y re-cifrados."
    else
        log_error "Error al re-cifrar."
        exit 1
    fi
}

# Mostrar ayuda
show_help() {
    echo "Uso: $0 <comando>"
    echo ""
    echo "Comandos:"
    echo "  encrypt    Cifra secrets.env -> secrets.env.age"
    echo "  decrypt    Descifra secrets.env.age -> secrets.env"
    echo "  edit       Edita secrets.env.age (descifra, edita, re-cifra)"
    echo "  view       Muestra el contenido cifrado sin guardar"
    echo ""
}

# Main
case "${1:-help}" in
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
    *)
        show_help
        ;;
esac
