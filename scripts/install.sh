#!/bin/bash

# =============================================================================
# 🔐 VAULTWARDEN INSTALLER
# =============================================================================
# Diseñado para una experiencia de usuario premium y configuración profesional.
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
    clear
    echo -e "${CYAN}"
    echo "    █░█ ▄▀█ █░█ █░░ ▀█▀ █░█ ▄▀█ █▀█ █▀▄ █▀▀ █▄░█"
    echo "    ▀▄▀ █▀█ █▄█ █▄▄ ░█░ ▀▄▀ █▀█ █▀▄ █▄▀ ██▄ █░▀█"
    echo -e "${NC}"
    echo -e "${BOLD}      BEYOND SECURITY — SELF-HOSTED STACK${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# --- FUNCIONES DE LOGGING ---
log_section() { echo -e "\n${BOLD}${MAGENTA}◈ $1${NC}\n" ; }
log_info()    { echo -e "  ${BLUE}ℹ${NC} $1" ; }
log_success() { echo -e "  ${GREEN}✔${NC} $1" ; }
log_warning() { echo -e "  ${YELLOW}⚠${NC} $1" ; }
log_error()   { echo -e "  ${RED}✖${NC} $1" ; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"
CRON_SCHEDULE="${2:-0 3 * * *}"

# Ubicaciones de clave AGE
AGE_KEY_LOCATIONS=(
    "${AGE_KEY_FILE:-}"
    "$PROJECT_DIR/.age-key"
    "$HOME/.age/vaultwarden.key"
    "/root/.age/vaultwarden.key"
)

# --- BUSCAR CLAVE AGE ---
find_age_key() {
    for key_path in "${AGE_KEY_LOCATIONS[@]}"; do
        if [[ -n "$key_path" && -f "$key_path" ]]; then
            echo "$key_path"
            return 0
        fi
    done
    return 1
}

# --- VERIFICAR DEPENDENCIAS ---
check_dependencies() {
    log_section "VERIFICANDO INFRAESTRUCTURA"
    
    local missing=()
    local deps=("age" "rclone" "curl" "docker" "bw")
    
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
            log_error "Falta: $cmd"
        else
            log_success "$cmd instalado"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        log_warning "Para instalar las dependencias faltantes:"
        echo -e "  ${CYAN}Debian/Ubuntu:${NC} sudo apt install age rclone curl git && npm install -g @bitwarden/cli"
        echo -e "  ${CYAN}Fedora:${NC} sudo dnf install age rclone curl git && npm install -g @bitwarden/cli"
        return 1
    fi
}

# --- CONFIGURAR ENTORNO (.env) ---
setup_env() {
    log_section "CONFIGURACIÓN DE ENTORNO"
    
    if [[ -f "$PROJECT_DIR/.env" || -f "$PROJECT_DIR/.env.age" ]]; then
        log_success "Archivo de configuración detectado."
        return 0
    fi
    
    log_warning "No se encontró el archivo .env"
    read -p "    ¿Deseas crear uno nuevo desde la plantilla .env.example? [S/n]: " -r response
    response=${response:-S}
    
    if [[ "$response" =~ ^[Ss]$ ]]; then
        cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
        log_success "Archivo .env creado. Por favor, edítalo antes de iniciar."
    fi
}

# --- CONFIGURAR CRON ---
setup_cron() {
    local schedule="${1:-$CRON_SCHEDULE}"
    log_section "PROGRAMACIÓN DE BACKUPS"
    
    # Determinar ruta de log escribible
    local log_path="/var/log/vaultwarden_backup.log"
    if [[ ! -w "/var/log" ]]; then
        log_path="$PROJECT_DIR/backup.log"
        log_info "Usando log local: $log_path"
    fi

    # Validar formato básico de cron (5 campos)
    if [[ "$schedule" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]]; then
        schedule="$schedule * * *"
    fi

    local CRON_CMD="$BACKUP_SCRIPT >> $log_path 2>&1"
    local CRON_ENTRY="$schedule $CRON_CMD"
    
    local CURRENT_CRON=""
    CURRENT_CRON=$(crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT" || true)
    
    if crontab -l 2>/dev/null | grep -q "$BACKUP_SCRIPT"; then
        log_warning "Ya existe un backup programado."
        read -p "    ¿Deseas actualizar el horario? [s/N]: " -r response
        if [[ ! "$response" =~ ^[Ss]$ ]]; then
            log_info "Manteniendo cron actual."
            return 0
        fi
    fi
    
    if [[ -n "$CURRENT_CRON" ]]; then
        echo -e "${CURRENT_CRON}\n${CRON_ENTRY}" | crontab -
    else
        echo "$CRON_ENTRY" | crontab -
    fi
    
    log_success "Backup programado correctamente: ${BOLD}$schedule${NC}"
}

# --- MOSTRAR ESTADO ---
show_status() {
    log_section "SISTEMA DE SALUD"
    
    # Dependencias
    echo -e "  ${BOLD}Core Services:${NC}"
    for cmd in age rclone curl docker bw; do
        if command -v "$cmd" &> /dev/null; then
            echo -e "    ${GREEN}●${NC} $cmd"
        else
            echo -e "    ${RED}○${NC} $cmd"
        fi
    done
    
    echo ""
    echo -e "  ${BOLD}Seguridad (AGE):${NC}"
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    if [[ -n "$AGE_KEY" ]]; then
        log_success "Clave activa: $AGE_KEY"
    else
        log_error "Clave privada no encontrada"
    fi
    
    echo ""
    echo -e "  ${BOLD}Configuración:${NC}"
    for file in .env.age .env docker-compose.yml; do
        if [[ -f "$PROJECT_DIR/$file" ]]; then
            echo -e "    ${GREEN}●${NC} $file"
        else
            echo -e "    ${YELLOW}◌${NC} $file (vacío)"
        fi
    done
    
    echo ""
}

# --- INSTALACIÓN COMPLETA ---
full_install() {
    show_banner
    
    check_dependencies || true
    
    log_section "CONFIGURACIÓN DE SEGURIDAD"
    if ! find_age_key > /dev/null; then
        log_warning "No se detectó una clave AGE."
        read -p "    ¿Generar una nueva clave maestra ahora? [S/n]: " -r response
        response=${response:-S}
        if [[ "$response" =~ ^[Ss]$ ]]; then
            "$SCRIPT_DIR/manage_secrets.sh" setup
        fi
    else
        log_success "Clave de seguridad detectada correctamente."
    fi
    
    setup_env
    setup_cron "$CRON_SCHEDULE"
    
    show_status
    
    log_section "FINALIZACIÓN"
    echo -e "  ${BOLD}Pasos Finales:${NC}"
    echo -e "  1. Configura tus credenciales en el archivo ${CYAN}.env${NC}"
    echo -e "  2. Cifra tus secretos: ${CYAN}./scripts/manage_secrets.sh encrypt${NC}"
    echo -e "  3. Inicia el motor: ${CYAN}./scripts/start.sh${NC}"
    echo ""
    echo -e "  ${YELLOW}${BOLD}⚠ RECUERDA:${NC} Respalda tu clave AGE con ${CYAN}./scripts/manage_secrets.sh show-key${NC}"
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# --- MAIN ---
case "${1:-}" in
    --deps)   check_dependencies ;;
    --cron)   setup_cron "${2:-$CRON_SCHEDULE}" ;;
    --status) show_status ;;
    --help|-h)
        echo "Uso: $0 [opción]"
        echo "  (sin args)   Instalación guiada"
        echo "  --deps       Verificar herramientas base"
        echo "  --cron       Configurar horario de backup"
        echo "  --status     Diagnóstico de salud"
        ;;
    "")       full_install ;;
    *)        echo "Opción inválida. Usa --help" ; exit 1 ;;
esac
