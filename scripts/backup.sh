#!/bin/bash

# =============================================================================
# VAULTWARDEN BACKUP SCRIPT
# =============================================================================
# Exporta la bóveda de Vaultwarden, la cifra con AGE y la sube a Google Drive
# usando rclone. Notifica por Telegram el resultado.
#
# Requisitos:
#   - age (apt install age)
#   - bw (Bitwarden CLI)
#   - rclone (configurado con remote gdrive)
#   - curl (para Telegram)
#
# Uso:
#   ./backup.sh              # Ejecución interactiva (pide passphrase)
#   AGE_PASSPHRASE="xxx" ./backup.sh  # Ejecución automática (cron)
# =============================================================================

set -euo pipefail

# --- PATH PARA CRON ---
# Cron tiene un PATH limitado, añadimos NVM para encontrar bw (Bitwarden CLI)
if [[ -d "/root/.nvm/versions/node" ]]; then
    NODE_PATH=$(find /root/.nvm/versions/node -maxdepth 1 -type d -name "v*" | sort -V | tail -1)
    if [[ -n "$NODE_PATH" ]]; then
        export PATH="$NODE_PATH/bin:$PATH"
    fi
fi

# --- CONFIGURACIÓN ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="$PROJECT_DIR/.env.age"
LOG_FILE="/var/log/vaultwarden_backup.log"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_JSON="/tmp/vw_backup_${TIMESTAMP}.json"
BACKUP_ENCRYPTED="/tmp/vw_backup_${TIMESTAMP}.json.age"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- FUNCIONES DE LOGGING ---
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$1"; echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { log "SUCCESS" "$1"; echo -e "${GREEN}✓${NC} $1"; }
log_warning() { log "WARNING" "$1"; echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { log "ERROR" "$1"; echo -e "${RED}✗${NC} $1"; }

# --- VERIFICACIÓN DE DEPENDENCIAS ---
check_dependencies() {
    local missing=()
    
    for cmd in age bw rclone curl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Faltan dependencias: ${missing[*]}"
        echo ""
        echo "Instalar con:"
        echo "  apt install age rclone curl"
        echo "  # Para bw (Bitwarden CLI):"
        echo "  npm install -g @bitwarden/cli"
        exit 1
    fi
}

# --- CARGAR SECRETOS ---
load_secrets() {
    if [[ ! -f "$SECRETS_FILE" ]]; then
        log_error "No existe el archivo de secretos: $SECRETS_FILE"
        echo "  Ejecuta: ./manage_secrets.sh encrypt"
        exit 1
    fi
    
    log_info "Descifrando secretos..."
    
    # Si AGE_PASSPHRASE está definida (cron), usarla automáticamente
    # age soporta la variable AGE_PASSPHRASE nativamente con el flag -p
    if [[ -n "${AGE_PASSPHRASE:-}" ]]; then
        # Exportar para que age la lea automáticamente
        export AGE_PASSPHRASE
        DECRYPTED=$(age -d -p "$SECRETS_FILE" 2>&1)
        if [[ $? -ne 0 ]]; then
            log_error "Error al descifrar secretos: $DECRYPTED"
            exit 1
        fi
    else
        # Modo interactivo - pide passphrase en terminal
        DECRYPTED=$(age -d -p "$SECRETS_FILE")
    fi
    
    # Cargar variables en memoria (no en disco)
    while IFS='=' read -r key value; do
        # Ignorar líneas vacías y comentarios
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        # Eliminar espacios y exportar
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        export "$key=$value"
    done <<< "$DECRYPTED"
    
    log_success "Secretos cargados en memoria"
}

# --- TELEGRAM ---
send_telegram() {
    local message="$1"
    local emoji="${2:-}"
    
    if [[ -z "${TELEGRAM_TOKEN:-}" ]] || [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        log_warning "Telegram no configurado, saltando notificación"
        return 0
    fi
    
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${emoji}${message}" \
        -d "parse_mode=HTML" > /dev/null 2>&1 || true
}

# --- CLEANUP ---
cleanup() {
    log_info "Limpiando archivos temporales..."
    rm -f "$BACKUP_JSON" "$BACKUP_ENCRYPTED" 2>/dev/null || true
    
    # Cerrar sesión de bw si está logueado
    bw logout > /dev/null 2>&1 || true
}

# Asegurar limpieza al salir
trap cleanup EXIT

# --- EXPORTAR VAULT ---
export_vault() {
    log_info "Configurando servidor Vaultwarden..."
    bw config server "$BW_HOST" > /dev/null
    
    log_info "Iniciando sesión con API Key..."
    export BW_CLIENTID="$BW_CLIENTID"
    export BW_CLIENTSECRET="$BW_CLIENTSECRET"
    
    if ! bw login --apikey > /dev/null 2>&1; then
        log_error "Error al iniciar sesión. Verifica BW_CLIENTID y BW_CLIENTSECRET"
        return 1
    fi
    
    log_info "Desbloqueando bóveda..."
    export BW_PASSWORD="$BW_PASSWORD"
    BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null)
    
    if [[ -z "$BW_SESSION" ]]; then
        log_error "Error al desbloquear la bóveda. Verifica BW_PASSWORD"
        return 1
    fi
    
    export BW_SESSION
    
    log_info "Exportando bóveda a JSON..."
    if ! bw export --format json --output "$BACKUP_JSON" > /dev/null 2>&1; then
        log_error "Error al exportar la bóveda"
        return 1
    fi
    
    if [[ ! -f "$BACKUP_JSON" ]]; then
        log_error "No se generó el archivo de backup"
        return 1
    fi
    
    log_success "Bóveda exportada: $BACKUP_JSON"
    return 0
}

# --- CIFRAR BACKUP ---
encrypt_backup() {
    log_info "Cifrando backup con AGE..."
    
    # AGE_PASSPHRASE ya está exportada, age la usará automáticamente con -p
    # Si no está definida, age pedirá passphrase (modo interactivo)
    age -p -o "$BACKUP_ENCRYPTED" "$BACKUP_JSON"
    
    if [[ -f "$BACKUP_ENCRYPTED" ]]; then
        log_success "Backup cifrado: $BACKUP_ENCRYPTED"
        # Eliminar JSON plano inmediatamente
        rm -f "$BACKUP_JSON"
        return 0
    else
        log_error "Error al cifrar el backup"
        return 1
    fi
}

# --- SUBIR A DRIVE ---
upload_to_drive() {
    local remote="${RCLONE_REMOTE:-gdrive:Backups/Vaultwarden}"
    local retention="${BACKUP_RETENTION_DAYS:-7}"
    
    log_info "Subiendo a $remote..."
    
    if ! rclone copy "$BACKUP_ENCRYPTED" "$remote" --progress; then
        log_error "Error al subir el backup a la nube"
        return 1
    fi
    
    log_success "Backup subido exitosamente"
    
    # Limpiar backups antiguos
    log_info "Eliminando backups de más de ${retention} días..."
    rclone delete --min-age "${retention}d" "$remote" 2>/dev/null || true
    
    return 0
}

# --- MAIN ---
main() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  🔐 VAULTWARDEN BACKUP - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    check_dependencies
    load_secrets
    
    local start_time
    start_time=$(date +%s)
    
    if export_vault && encrypt_backup && upload_to_drive; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local file_size
        file_size=$(du -h "$BACKUP_ENCRYPTED" 2>/dev/null | cut -f1 || echo "N/A")
        
        log_success "¡Backup completado en ${duration}s!"
        
        send_telegram "✅ <b>Backup Vaultwarden Exitoso</b>
📅 Fecha: $TIMESTAMP
💾 Tamaño: $file_size
⏱ Duración: ${duration}s"
        
    else
        log_error "Backup fallido"
        
        send_telegram "❌ <b>ERROR: Backup Vaultwarden Fallido</b>
📅 Fecha: $TIMESTAMP
📋 Revisa los logs: $LOG_FILE" "🚨 "
        
        exit 1
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

main "$@"
