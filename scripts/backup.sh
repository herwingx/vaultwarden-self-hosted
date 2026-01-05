#!/bin/bash

# =============================================================================
# VAULTWARDEN BACKUP SCRIPT
# =============================================================================
# Exporta la bóveda de Vaultwarden, la cifra con AGE y la sube a Google Drive
# usando rclone. Notifica por Telegram el resultado.
#
# ESTRATEGIA DE CIFRADO:
#   Este script usa AGE con IDENTITY FILES (claves) en lugar de passphrase.
#   Esto permite ejecución automática sin terminal (cron/systemd).
#
# Requisitos:
#   - age (apt install age / dnf install age)
#   - bw (Bitwarden CLI)
#   - rclone (configurado con remote gdrive)
#   - curl (para Telegram)
#
# Configuración inicial:
#   1. Generar clave: age-keygen -o ~/.age/vaultwarden.key
#   2. Cifrar secretos: age -R ~/.age/vaultwarden.key.pub -o .env.age secrets.env
#   3. Configurar AGE_KEY_FILE en crontab o como variable de entorno
#
# Uso:
#   ./backup.sh                                    # Usa ~/.age/vaultwarden.key
#   AGE_KEY_FILE=/path/to/key ./backup.sh          # Clave personalizada
#   AGE_PASSPHRASE="xxx" ./backup.sh               # Modo passphrase (interactivo)
# =============================================================================

set -euo pipefail

# --- PATH PARA CRON ---
# Cron tiene un PATH muy limitado, añadimos rutas estándar del sistema
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Buscar NVM en ubicaciones comunes (root y usuario normal)
NVM_DIRS=(
    "$HOME/.nvm/versions/node"           # Usuario normal
    "/root/.nvm/versions/node"           # Root
    "/home/$USER/.nvm/versions/node"     # Alternativa usuario
)

for NVM_DIR in "${NVM_DIRS[@]}"; do
    if [[ -d "$NVM_DIR" ]]; then
        NODE_PATH=$(find "$NVM_DIR" -maxdepth 1 -type d -name "v*" 2>/dev/null | sort -V | tail -1)
        if [[ -n "$NODE_PATH" ]]; then
            export PATH="$NODE_PATH/bin:$PATH"
            break
        fi
    fi
done

# Fallback: buscar bw en ubicaciones conocidas
if ! command -v bw &> /dev/null; then
    for BW_PATH in /usr/local/bin/bw /usr/local/sbin/bw /usr/bin/bw; do
        if [[ -x "$BW_PATH" ]]; then
            export PATH="$(dirname "$BW_PATH"):$PATH"
            break
        fi
    done
fi

# --- CONFIGURACIÓN ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="$PROJECT_DIR/.env.age"
LOG_FILE="/var/log/vaultwarden_backup.log"

# Ubicaciones de clave AGE (en orden de prioridad)
AGE_KEY_LOCATIONS=(
    "${AGE_KEY_FILE:-}"                          # Variable de entorno
    "$PROJECT_DIR/.age-key"                       # En el proyecto
    "$HOME/.age/vaultwarden.key"                  # Usuario normal
    "/root/.age/vaultwarden.key"                  # Root
)

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
        echo "  dnf install age rclone curl   # Fedora"
        echo "  apt install age rclone curl   # Ubuntu/Debian"
        echo "  # Para bw (Bitwarden CLI):"
        echo "  npm install -g @bitwarden/cli"
        exit 1
    fi
}

# --- ENCONTRAR CLAVE AGE ---
find_age_key() {
    for key_path in "${AGE_KEY_LOCATIONS[@]}"; do
        if [[ -n "$key_path" && -f "$key_path" ]]; then
            echo "$key_path"
            return 0
        fi
    done
    return 1
}

# --- CARGAR SECRETOS ---
load_secrets() {
    if [[ ! -f "$SECRETS_FILE" ]]; then
        log_error "No existe el archivo de secretos: $SECRETS_FILE"
        echo "  Ejecuta: ./manage_secrets.sh encrypt"
        exit 1
    fi
    
    log_info "Descifrando secretos..."
    
    local DECRYPTED=""
    local AGE_EXIT_CODE=0
    local AGE_KEY=""
    
    # Buscar clave de identidad AGE
    AGE_KEY=$(find_age_key) || true
    
    if [[ -n "$AGE_KEY" ]]; then
        # Modo IDENTITY FILE (recomendado para cron)
        log_info "Usando clave: $AGE_KEY"
        DECRYPTED=$(age -d -i "$AGE_KEY" "$SECRETS_FILE" 2>&1) || AGE_EXIT_CODE=$?
        
    elif [[ -n "${AGE_PASSPHRASE:-}" ]]; then
        # Modo PASSPHRASE con archivo temporal seguro
        log_info "Usando passphrase (${#AGE_PASSPHRASE} caracteres)"
        
        # Crear archivo temporal seguro para passphrase
        local PASS_FIFO
        PASS_FIFO=$(mktemp -u)
        mkfifo -m 600 "$PASS_FIFO"
        
        # Escribir passphrase en background y descifrar
        echo "$AGE_PASSPHRASE" > "$PASS_FIFO" &
        DECRYPTED=$(age -d "$SECRETS_FILE" < "$PASS_FIFO" 2>&1) || AGE_EXIT_CODE=$?
        
        rm -f "$PASS_FIFO"
        
    else
        # Modo INTERACTIVO (terminal)
        log_info "Modo interactivo - ingresa la passphrase:"
        DECRYPTED=$(age -d "$SECRETS_FILE") || AGE_EXIT_CODE=$?
    fi
    
    if [[ $AGE_EXIT_CODE -ne 0 ]]; then
        log_error "Error al descifrar (exit: $AGE_EXIT_CODE): $DECRYPTED"
        echo ""
        echo "Soluciones:"
        echo "  1. Crear clave AGE: age-keygen -o ~/.age/vaultwarden.key"
        echo "  2. Re-cifrar secretos con la clave pública"
        echo "  3. O definir AGE_KEY_FILE=/ruta/a/clave"
        exit 1
    fi
    
    # Verificar que tenemos contenido descifrado
    if [[ -z "$DECRYPTED" ]]; then
        log_error "El archivo descifrado está vacío"
        exit 1
    fi
    
    # Cargar variables en memoria (no en disco)
    local loaded_count=0
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # Ignorar líneas vacías y comentarios
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        # Eliminar espacios
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        # Solo exportar si key no está vacía
        if [[ -n "$key" ]]; then
            export "$key=$value"
            loaded_count=$((loaded_count + 1))
        fi
    done <<< "$DECRYPTED"
    
    log_success "Secretos cargados en memoria ($loaded_count variables)"
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
    
    local AGE_KEY=""
    local ENCRYPT_EXIT=0
    
    # Buscar clave de identidad AGE
    AGE_KEY=$(find_age_key) || true
    
    if [[ -n "$AGE_KEY" ]]; then
        # Extraer clave pública del archivo de identidad
        local PUB_KEY
        PUB_KEY=$(grep -o 'age1[a-z0-9]*' "$AGE_KEY" | head -1 || grep 'public key' "$AGE_KEY" | awk '{print $NF}')
        
        if [[ -z "$PUB_KEY" ]]; then
            # Generar clave pública desde la privada
            PUB_KEY=$(age-keygen -y "$AGE_KEY" 2>/dev/null)
        fi
        
        log_info "Cifrando con clave pública"
        age -r "$PUB_KEY" -o "$BACKUP_ENCRYPTED" "$BACKUP_JSON" || ENCRYPT_EXIT=$?
        
    elif [[ -n "${AGE_PASSPHRASE:-}" ]]; then
        # Modo PASSPHRASE con FIFO
        log_info "Cifrando con passphrase"
        
        local PASS_FIFO
        PASS_FIFO=$(mktemp -u)
        mkfifo -m 600 "$PASS_FIFO"
        
        echo "$AGE_PASSPHRASE" > "$PASS_FIFO" &
        age -e -p -o "$BACKUP_ENCRYPTED" "$BACKUP_JSON" < "$PASS_FIFO" || ENCRYPT_EXIT=$?
        
        rm -f "$PASS_FIFO"
    else
        # Modo interactivo
        age -e -p -o "$BACKUP_ENCRYPTED" "$BACKUP_JSON" || ENCRYPT_EXIT=$?
    fi
    
    if [[ $ENCRYPT_EXIT -ne 0 ]]; then
        log_error "Error al cifrar el backup (exit: $ENCRYPT_EXIT)"
        return 1
    fi
    
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
