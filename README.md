# 🔐 Vaultwarden Self-Hosted

> **Gestor de contraseñas auto-hospedado** — Alternativa ligera y compatible con Bitwarden, con backups cifrados automáticos a la nube.

[![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)](https://www.docker.com/)
[![Vaultwarden](https://img.shields.io/badge/Vaultwarden-175DDC?style=flat-square&logo=bitwarden&logoColor=white)](https://github.com/dani-garcia/vaultwarden)
[![AGE](https://img.shields.io/badge/AGE_Encryption-2D3748?style=flat-square&logo=gnuprivacyguard&logoColor=white)](https://age-encryption.org/)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

---

## ✨ Características

| Característica                | Descripción                                            |
| :---------------------------- | :----------------------------------------------------- |
| 🐳 **Docker Compose**          | Despliegue simple con un solo comando                  |
| 🌐 **Acceso Flexible**         | Cloudflare Tunnel, Tailscale, Reverse Proxy o IP local |
| 🔐 **Cifrado AGE**             | Secretos y backups protegidos con passphrase           |
| ☁️ **Backup a la Nube**        | Respaldos automáticos con rclone (Drive, S3, etc.)     |
| 📱 **Notificaciones Telegram** | Alertas de estado en cada backup                       |
| ⏰ **Cron Automatizado**       | Backups diarios sin intervención                       |
| 🧹 **Retención Inteligente**   | Limpieza automática de backups antiguos                |

---

## 🚀 Inicio Rápido

### Requisitos Previos

- **Servidor Linux** con Docker instalado (Ubuntu, Debian, Proxmox LXC, Raspberry Pi, etc.)
- **Dominio** (opcional, para acceso remoto con HTTPS)
- Herramientas: `age`, `rclone`, `bw` (Bitwarden CLI), `curl`

### 1. Clonar el repositorio

```bash
git clone https://github.com/herwingx/vaultwarden-proxmox.git /opt/vaultwarden
cd /opt/vaultwarden
```

### 2. Instalar dependencias

```bash
# Instalar herramientas necesarias
apt update && apt install -y age rclone curl

# Instalar Bitwarden CLI
npm install -g @bitwarden/cli
```

O si tienes los [dotfiles](https://github.com/herwingx/dotfiles):

```bash
cd ~/dotfiles && ./install.sh
```

### 3. Configurar variables de entorno

```bash
cp .env.example .env
nano .env
```

### 4. Levantar Vaultwarden

```bash
./scripts/start.sh
```

### 5. Configurar acceso (elige una opción)

<details>
<summary><strong>🔷 Opción A: Cloudflare Tunnel (Recomendado para dominio propio)</strong></summary>

Sin abrir puertos en tu router. Requiere cuenta en Cloudflare.

1. En **Cloudflare Zero Trust** → **Tunnels** → crear tunnel
2. Añadir **Public Hostname**:

| Campo     | Valor                   |
| :-------- | :---------------------- |
| Subdomain | `vault`                 |
| Domain    | `tudominio.com`         |
| Service   | `http://vaultwarden:80` |

3. Copiar el token del tunnel a `docker-compose.yml`:

```yaml
cloudflared:
  environment:
    - TUNNEL_TOKEN=tu_token_aqui
```

</details>

<details>
<summary><strong>🟣 Opción B: Tailscale (Red privada entre dispositivos)</strong></summary>

Acceso seguro solo desde tus dispositivos con Tailscale instalado.

1. Instalar Tailscale en el servidor:
```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up
```

2. Acceder desde cualquier dispositivo con Tailscale:
```
http://100.x.x.x:8080
```

> 📘 Tu IP de Tailscale la encuentras con `tailscale ip -4`

</details>

<details>
<summary><strong>🟢 Opción C: Reverse Proxy (Nginx, Traefik, Caddy)</strong></summary>

Si ya tienes un reverse proxy configurado.

**Ejemplo con Nginx:**

```nginx
server {
    listen 443 ssl;
    server_name vault.tudominio.com;

    ssl_certificate /etc/letsencrypt/live/vault.tudominio.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/vault.tudominio.com/privkey.pem;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

</details>

<details>
<summary><strong>🟡 Opción D: Acceso Local (Solo red interna)</strong></summary>

Acceso solo desde tu red local, sin exposición a internet.

```bash
# Acceder directamente por IP
http://192.168.1.100:8080
```

> ⚠️ **Nota**: Sin HTTPS, las extensiones de Bitwarden pueden no funcionar. Considera usar Tailscale o un certificado local.

</details>

### 6. Crear tu cuenta

Accede a tu instancia (según la opción elegida) y crea tu cuenta.

### 7. Obtener API Keys

1. Ve a **⚙️ Ajustes** → **Seguridad** → **Keys**
2. Click en **Ver API Key**
3. Copia el `client_id` y `client_secret`

### 8. Actualizar secretos

```bash
./scripts/manage_secrets.sh edit
```

Completa los valores:

```env
BW_HOST=https://vault.tudominio.com  # o tu IP/URL
BW_CLIENTID=user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
BW_CLIENTSECRET=el_secret_que_copiaste
BW_PASSWORD=tu_contraseña_maestra
```

### 9. Cerrar registros

Edita `docker-compose.yml`:

```yaml
- SIGNUPS_ALLOWED=false
```

Reinicia:

```bash
docker compose down && ./scripts/start.sh
```

### 10. Configurar backups automáticos

```bash
./scripts/install.sh --cron
```

Te pedirá la passphrase y configurará el backup diario a las 3:00 AM.

> ✅ **¡Listo!** Vaultwarden está corriendo con backups automáticos cifrados.

---

## 🔐 Configuración de Secretos

### 1. Copiar plantilla

```bash
cp .env.example .env
```

### 2. Editar con tus valores

```bash
nano .env
```

Variables principales:

```env
# API Keys (Vaultwarden -> Ajustes -> Seguridad -> Keys)
BW_HOST=https://vault.tudominio.com
BW_CLIENTID=user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
BW_CLIENTSECRET=tu_client_secret
BW_PASSWORD=tu_contraseña_maestra

# Telegram (Bot @BotFather, ID con @userinfobot)
TELEGRAM_TOKEN=123456:ABC-token
TELEGRAM_CHAT_ID=123456789

# Rclone (gdrive, s3, dropbox, etc.)
RCLONE_REMOTE=gdrive:Backups/Vaultwarden
```

### 3. Cifrar secretos

```bash
./scripts/manage_secrets.sh encrypt
```

Te pedirá una **passphrase** — recuérdala, la necesitarás para los backups.

---

## 📦 Backups Automatizados

### Ejecución manual (interactiva)

```bash
./scripts/backup.sh
```

### Ejecución automática (cron)

```bash
./scripts/install.sh --cron
```

O edita manualmente el crontab:

```bash
crontab -e
```

```bash
0 3 * * * AGE_PASSPHRASE="tu_passphrase" /opt/vaultwarden/scripts/backup.sh >> /var/log/vw_backup.log 2>&1
```

> 📘 **Nota**: La variable `AGE_PASSPHRASE` permite la ejecución sin interacción.

---

## 🔄 Restaurar Backup

### 1. Descargar el backup desde la nube

```bash
# Listar backups disponibles
rclone ls gdrive:Backups/Vaultwarden

# Descargar el más reciente (ejemplo)
rclone copy gdrive:Backups/Vaultwarden/vw_backup_20260102_030002.json.age /tmp/
```

### 2. Descifrar el archivo

```bash
age -d -o /tmp/vw_backup.json /tmp/vw_backup_20260102_030002.json.age
```

Te pedirá la passphrase que usaste para cifrar.

### 3. Importar en Vaultwarden

**Opción A: Desde la Web**

1. Accede a tu instancia de Vaultwarden
2. Ve a **⚙️ Ajustes** → **Importar datos**
3. Selecciona formato: **Bitwarden (json)**
4. Sube el archivo `/tmp/vw_backup.json`
5. Click en **Importar datos**

**Opción B: Desde CLI**

```bash
bw config server https://vault.tudominio.com
bw login
bw unlock
export BW_SESSION="tu_session_key"
bw import bitwardenjson /tmp/vw_backup.json
```

### 4. Limpiar archivo descifrado

```bash
rm -f /tmp/vw_backup.json /tmp/vw_backup_*.json.age
```

> ⚠️ **Importante**: Nunca dejes archivos JSON sin cifrar. Contienen todas tus contraseñas.

---

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTERNET                                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
      ┌───────▼───────┐ ┌───▼───┐ ┌───────▼───────┐
      │  Cloudflare   │ │Tailsc.│ │ Reverse Proxy │
      │    Tunnel     │ │  VPN  │ │ (Nginx/Caddy) │
      └───────┬───────┘ └───┬───┘ └───────┬───────┘
              └─────────────┼─────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                    TU SERVIDOR LINUX                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Docker                                │   │
│  │  ┌─────────────────────────────────────────────────┐    │   │
│  │  │              Vaultwarden                         │    │   │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────────────┐  │    │   │
│  │  │  │  API    │  │  Web    │  │   SQLite DB     │  │    │   │
│  │  │  │  :80    │  │  Vault  │  │   ./data        │  │    │   │
│  │  │  └─────────┘  └─────────┘  └─────────────────┘  │    │   │
│  │  └─────────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │  backup.sh   │──│  AGE Cipher  │──│  rclone → Cloud      │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📁 Estructura del Proyecto

```
vaultwarden/
├── docker-compose.yml       # Configuración de Vaultwarden
├── .env.example             # Plantilla de variables
├── .env.age                 # 🔒 Secretos cifrados (va a Git)
├── data/                    # 🔒 Datos de Vaultwarden (NO va a Git)
├── scripts/
│   ├── install.sh           # Instalación y configuración
│   ├── start.sh             # Iniciar servicios
│   ├── backup.sh            # Backup automatizado
│   └── manage_secrets.sh    # Gestor de secretos
├── LICENSE
└── README.md
```

---

## 🔧 Comandos Útiles

```bash
# Instalación completa
./scripts/install.sh

# Levantar servicio
./scripts/start.sh

# Ver logs
docker compose logs -f

# Reiniciar
docker compose down && ./scripts/start.sh

# Gestión de secretos
./scripts/manage_secrets.sh encrypt    # Cifrar .env
./scripts/manage_secrets.sh decrypt    # Descifrar a .env
./scripts/manage_secrets.sh edit       # Editar y re-cifrar
./scripts/manage_secrets.sh view       # Ver sin guardar

# Backup manual
./scripts/backup.sh

# Configurar cron
./scripts/install.sh --cron

# Ver estado
./scripts/install.sh --status
```

---

## 📚 Documentación

| Documento                                                                                           | Descripción             |
| :-------------------------------------------------------------------------------------------------- | :---------------------- |
| [Vaultwarden Wiki](https://github.com/dani-garcia/vaultwarden/wiki)                                 | Documentación oficial   |
| [AGE Encryption](https://age-encryption.org/)                                                       | Cifrado moderno         |
| [Rclone Docs](https://rclone.org/docs/)                                                             | Sincronización con nube |
| [Tailscale](https://tailscale.com/kb/)                                                              | VPN mesh                |
| [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) | Túneles seguros         |

---

## 🛠️ Stack Tecnológico

**Servidor**
- **Vaultwarden**: Servidor compatible con Bitwarden (Rust)
- **Docker**: Contenedorización

**Seguridad**
- **AGE**: Cifrado de secretos y backups
- **Cloudflare Tunnel / Tailscale**: Acceso seguro (opcional)

**Backup**
- **Bitwarden CLI**: Exportación de bóveda
- **Rclone**: Sincronización con la nube
- **Telegram Bot API**: Notificaciones

---

## 🔒 Seguridad

- ✅ Secretos cifrados con AGE + passphrase
- ✅ Backups cifrados antes de subir a la nube
- ✅ Archivos sensibles excluidos de Git
- ✅ Registro deshabilitado después de crear cuenta
- ✅ Soporte para 2FA/TOTP
- ✅ Múltiples opciones de acceso seguro

---

## 🤝 Contribuir

1. Fork del repositorio
2. Crear rama: `git checkout -b feat/nueva-feature`
3. Commit: `git commit -m "feat: descripción"`
4. Push: `git push origin feat/nueva-feature`
5. Crear Pull Request

---

## 📄 Licencia

Este proyecto está bajo la licencia MIT. Ver [LICENSE](LICENSE) para más detalles.
