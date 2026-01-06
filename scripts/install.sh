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
#   ./install.sh --status # Mostrar estado
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"
CRON_SCHEDULE="${2:-0 3 * * *}"  # Default: 3:00 AM diario

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
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

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
    log_info "Verificando dependencias..."
    
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
        echo "Instalar con:"
        echo "  dnf install age rclone curl    # Fedora"
        echo "  apt install age rclone curl    # Ubuntu/Debian"
        echo "  npm install -g @bitwarden/cli  # Bitwarden CLI"
        echo ""
        return 1
    fi
    
    log_success "Todas las dependencias están instaladas"
}

# --- VERIFICAR CLAVE AGE ---
check_age_key() {
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    if [[ -z "$AGE_KEY" ]]; then
        log_warning "No se encontró clave AGE"
        echo ""
        echo "Opciones:"
        echo "  1. Generar nueva clave: ./manage_secrets.sh setup"
        echo "  2. Copiar desde otro servidor: scp user@server:~/.age/vaultwarden.key ~/.age/"
        echo "  3. Restaurar desde Bitwarden Cloud"
        echo ""
        return 1
    fi
    
    log_success "Clave AGE encontrada: $AGE_KEY"
    return 0
}

# --- CONFIGURAR CRON ---
setup_cron() {
    local schedule="${1:-$CRON_SCHEDULE}"
    log_info "Configurando cron para backups automáticos ($schedule)..."
    
    # Verificar que existe .env.age
    if [[ ! -f "$PROJECT_DIR/.env.age" ]]; then
        log_error "No existe .env.age"
        echo "  Ejecuta primero: ./manage_secrets.sh encrypt"
        return 1
    fi
    
    # Verificar que existe clave AGE
    if ! check_age_key; then
        log_error "Se requiere clave AGE para el cron"
        return 1
    fi
    
    # Con identity keys NO necesitamos passphrase
    # El script backup.sh encontrará la clave automáticamente
    local CRON_CMD="$BACKUP_SCRIPT >> /var/log/vaultwarden_backup.log 2>&1"
    local CRON_ENTRY="$schedule $CRON_CMD"
    
    # Obtener crontab actual (sin la entrada de backup si existe)
    local CURRENT_CRON=""
    CURRENT_CRON=$(crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT" || true)
    
    # Verificar si ya existía
    if crontab -l 2>/dev/null | grep -q "$BACKUP_SCRIPT"; then
        log_warning "Ya existe una entrada de cron para backup.sh"
        read -p "¿Reemplazar? [s/N]: " -r response
        if [[ ! "$response" =~ ^[Ss]$ ]]; then
            log_info "Cron no modificado"
            return 0
        fi
    fi
    
    # Validar formato básico de cron (5 campos)
    # Si el usuario solo escribió "27 9", asumir que son minutos y horas: "27 9 * * *"
    if [[ "$schedule" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]]; then
        schedule="$schedule * * *"
        log_info "Asumiendo formato diario: $schedule"
    fi

    local CRON_ENTRY="$schedule $CRON_CMD"

    # Escribir crontab y verificar error
    if [[ -n "$CURRENT_CRON" ]]; then
        if ! echo -e "${CURRENT_CRON}\n${CRON_ENTRY}" | crontab -; then
            log_error "Falló la instalación del cron. Verifica el formato: '$schedule'"
            return 1
        fi
    else
        if ! echo "$CRON_ENTRY" | crontab -; then
            log_error "Falló la instalación del cron. Verifica el formato: '$schedule'"
            return 1
        fi
    fi
    
    log_success "Cron configurado: $schedule"
    echo "  Backup programado para: $schedule"
    echo "  Log: /var/log/vaultwarden_backup.log"
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
    
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    log_info "Descifrando .env.age..."
    
    if [[ -n "$AGE_KEY" ]]; then
        log_info "Usando clave: $AGE_KEY"
        if age -d -i "$AGE_KEY" -o "$PROJECT_DIR/.env" "$PROJECT_DIR/.env.age"; then
            log_success "Archivo descifrado: .env"
        else
            log_error "Error al descifrar"
            return 1
        fi
    else
        log_info "Usando passphrase..."
        if age -d -o "$PROJECT_DIR/.env" "$PROJECT_DIR/.env.age"; then
            log_success "Archivo descifrado: .env"
        else
            log_error "Error al descifrar"
            return 1
        fi
    fi
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
    echo "Clave AGE:"
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    if [[ -n "$AGE_KEY" ]]; then
        echo -e "  ${GREEN}✓${NC} $AGE_KEY"
    else
        echo -e "  ${RED}✗${NC} No encontrada"
        echo "      Ejecuta: ./manage_secrets.sh setup"
    fi
    
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
    
    check_dependencies || true
    echo ""
    
    # Verificar clave AGE
    if ! check_age_key; then
        echo ""
        read -p "¿Generar nueva clave AGE ahora? [S/n]: " -r response
        response=${response:-S}
        if [[ "$response" =~ ^[Ss]$ ]]; then
            "$SCRIPT_DIR/manage_secrets.sh" setup
        fi
    fi
    echo ""
    
    # Descifrar .env si existe .env.age
    if [[ -f "$PROJECT_DIR/.env.age" ]] && [[ ! -f "$PROJECT_DIR/.env" ]]; then
        decrypt_env || true
        echo ""
    fi
    
    # Configurar cron
    read -p "¿Configurar backup automático diario? [S/n]: " -r response
    response=${response:-S}
    if [[ "$response" =~ ^[Ss]$ ]]; then
        read -p "Ingresa el horario cron (Default: 0 3 * * *): " -r user_schedule
        user_schedule=${user_schedule:-"0 3 * * *"}
        setup_cron "$user_schedule" || true
    fi
    
    show_status
    
    echo "Próximos pasos:"
    echo "  1. Editar .env si necesitas cambiar valores: nano .env"
    echo "  2. Levantar servicios: ./start.sh"
    echo "  3. Crear cuenta en tu instancia de Vaultwarden"
    echo "  4. Obtener API Keys y actualizar secretos"
    echo ""
    echo -e "${CYAN}💡 IMPORTANTE: Guarda tu clave AGE en Bitwarden Cloud${NC}"
    echo "   ./manage_secrets.sh show-key"
    echo ""
}

# --- AYUDA ---
show_help() {
    echo "Uso: $0 [opción]"
    echo ""
    echo "Opciones:"
    echo "  (sin args)   Instalación completa"
    echo "  --deps       Solo verificar dependencias"
    echo "  --cron [schedule] Solo configurar cron (opcional: '0 5 * * *')"
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
        setup_cron "${2:-$CRON_SCHEDULE}"
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
