#!/bin/bash

# =============================================================================
# INSTALL - Instalación y configuración de Vaultwarden
# =============================================================================
# Instala dependencias, configura cron y prepara el entorno.
#
# Uso:
#   ./install.sh          # Instalación completa
#   ./install.sh --deps   # Solo instalar dependencias
#   ./install.sh --cron   # Solo configurar cron
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"
CRON_SCHEDULE="0 3 * * *"  # 3:00 AM diario

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

# --- VERIFICAR DEPENDENCIAS ---
# Las dependencias se instalan via dotfiles, aquí solo verificamos
check_dependencies() {
    log_info "Verificando dependencias (instaladas via dotfiles)..."
    
    local missing=()
    
    for cmd in age rclone curl docker bw; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        else
            log_success "$cmd OK"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Faltan dependencias: ${missing[*]}"
        echo ""
        echo "Instala primero los dotfiles:"
        echo "  git clone https://github.com/herwingx/dotfiles.git"
        echo "  cd dotfiles && ./install.sh"
        echo ""
        return 1
    fi
    
    log_success "Todas las dependencias están instaladas"
}

# --- CONFIGURAR CRON ---
setup_cron() {
    log_info "Configurando cron para backups automáticos..."
    
    # Verificar que existe .env.age
    if [[ ! -f "$PROJECT_DIR/.env.age" ]]; then
        log_error "No existe .env.age"
        echo "  Ejecuta primero: ./manage_secrets.sh encrypt"
        return 1
    fi
    
    # Pedir passphrase para el cron
    echo ""
    read -sp "Ingresa la passphrase de AGE (para el cron): " AGE_PASS
    echo ""
    
    if [[ -z "$AGE_PASS" ]]; then
        log_error "La passphrase no puede estar vacía"
        return 1
    fi
    
    # Crear entrada de cron
    local CRON_CMD="AGE_PASSPHRASE=\"$AGE_PASS\" $BACKUP_SCRIPT >> /var/log/vaultwarden_backup.log 2>&1"
    
    # Verificar si ya existe
    if crontab -l 2>/dev/null | grep -q "$BACKUP_SCRIPT"; then
        log_warning "Ya existe una entrada de cron para backup.sh"
        read -p "¿Reemplazar? [s/N]: " -r response
        if [[ ! "$response" =~ ^[Ss]$ ]]; then
            log_info "Cron no modificado"
            return 0
        fi
        # Eliminar entrada existente
        crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT" | crontab -
    fi
    
    # Agregar nueva entrada
    (crontab -l 2>/dev/null; echo "$CRON_SCHEDULE $CRON_CMD") | crontab -
    
    log_success "Cron configurado: $CRON_SCHEDULE"
    echo "  Backup diario a las 3:00 AM"
}

# --- DESCIFRAR .env.age ---
decrypt_env() {
    if [[ ! -f "$PROJECT_DIR/.env.age" ]]; then
        log_error "No existe .env.age"
        return 1
    fi
    
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        log_warning "Ya existe .env"
        read -p "¿Sobrescribir? [s/N]: " -r response
        if [[ ! "$response" =~ ^[Ss]$ ]]; then
            return 0
        fi
    fi
    
    log_info "Descifrando .env.age..."
    age -d -o "$PROJECT_DIR/.env" "$PROJECT_DIR/.env.age"
    log_success "Archivo descifrado: .env"
}

# --- MOSTRAR ESTADO ---
show_status() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  📋 Estado de la instalación"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Dependencias
    echo "Dependencias:"
    for cmd in age rclone curl docker bw; do
        if command -v "$cmd" &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} $cmd"
        else
            echo -e "  ${RED}✗${NC} $cmd"
        fi
    done
    
    echo ""
    echo "Archivos:"
    for file in .env.age .env docker-compose.yml; do
        if [[ -f "$PROJECT_DIR/$file" ]]; then
            echo -e "  ${GREEN}✓${NC} $file"
        else
            echo -e "  ${YELLOW}○${NC} $file (no existe)"
        fi
    done
    
    echo ""
    echo "Cron:"
    if crontab -l 2>/dev/null | grep -q "$BACKUP_SCRIPT"; then
        echo -e "  ${GREEN}✓${NC} Backup programado"
        crontab -l 2>/dev/null | grep "$BACKUP_SCRIPT" | sed 's/^/      /'
    else
        echo -e "  ${YELLOW}○${NC} No configurado"
    fi
    
    echo ""
}

# --- INSTALACIÓN COMPLETA ---
full_install() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  🔐 VAULTWARDEN - Instalación"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    check_dependencies
    echo ""
    
    # Descifrar .env si existe .env.age
    if [[ -f "$PROJECT_DIR/.env.age" ]] && [[ ! -f "$PROJECT_DIR/.env" ]]; then
        decrypt_env
        echo ""
    fi
    
    # Configurar cron
    read -p "¿Configurar backup automático diario? [S/n]: " -r response
    response=${response:-S}
    if [[ "$response" =~ ^[Ss]$ ]]; then
        setup_cron
    fi
    
    show_status
    
    echo "Próximos pasos:"
    echo "  1. Editar .env si necesitas cambiar valores: nano .env"
    echo "  2. Levantar servicios: ./start.sh"
    echo "  3. Crear cuenta en: https://vaultwarden.herwingx.dev"
    echo "  4. Obtener API Keys y actualizar .env"
    echo ""
}

# --- AYUDA ---
show_help() {
    echo "Uso: $0 [opción]"
    echo ""
    echo "Opciones:"
    echo "  (sin args)   Instalación completa"
    echo "  --deps       Solo instalar dependencias"
    echo "  --cron       Solo configurar cron"
    echo "  --decrypt    Descifrar .env.age a .env"
    echo "  --status     Mostrar estado"
    echo ""
}

# --- MAIN ---
case "${1:-}" in
    --deps)
        check_dependencies
        ;;
    --cron)
        setup_cron
        ;;
    --decrypt)
        decrypt_env
        ;;
    --status)
        show_status
        ;;
    --help|-h)
        show_help
        ;;
    "")
        full_install
        ;;
    *)
        log_error "Opción desconocida: $1"
        show_help
        exit 1
        ;;
esac
