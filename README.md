# 🔐 Vaultwarden Proxmox

> **Gestor de contraseñas auto-hospedado** — Alternativa ligera y compatible con Bitwarden, desplegado en Proxmox con backups cifrados automáticos.

[![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)](https://www.docker.com/)
[![Vaultwarden](https://img.shields.io/badge/Vaultwarden-175DDC?style=flat-square&logo=bitwarden&logoColor=white)](https://github.com/dani-garcia/vaultwarden)
[![Cloudflare](https://img.shields.io/badge/Cloudflare_Tunnel-F38020?style=flat-square&logo=cloudflare&logoColor=white)](https://www.cloudflare.com/)
[![AGE](https://img.shields.io/badge/AGE_Encryption-2D3748?style=flat-square&logo=gnuprivacyguard&logoColor=white)](https://age-encryption.org/)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

---

## ✨ Características

| Característica                | Descripción                                      |
| :---------------------------- | :----------------------------------------------- |
| 🐳 **Docker Compose**          | Despliegue simple con un solo comando            |
| 🔒 **Cloudflare Tunnel**       | Exposición segura sin abrir puertos en el router |
| 🔐 **Cifrado AGE**             | Secretos y backups protegidos con passphrase     |
| ☁️ **Backup a Google Drive**   | Respaldos automáticos con rclone                 |
| 📱 **Notificaciones Telegram** | Alertas de estado en cada backup                 |
| ⏰ **Cron Automatizado**       | Backups diarios sin intervención                 |
| 🧹 **Retención Inteligente**   | Limpieza automática de backups antiguos          |

---

## 🚀 Inicio Rápido

### Requisitos Previos

- **Proxmox LXC** con Docker instalado
- **Cloudflare** con dominio configurado
- **[dotfiles](https://github.com/herwingx/dotfiles)** instalados (incluye `age`, `rclone`, `bw`)

### 0. Instalar dotfiles (si no los tienes)

```bash
git clone https://github.com/herwingx/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
```

> 📘 Los dotfiles instalan y configuran: `age`, `rclone`, `bw` (Bitwarden CLI) y `curl`.

### 1. Clonar el repositorio

```bash
git clone https://github.com/herwingx/vaultwarden-proxmox.git /opt/vaultwarden
cd /opt/vaultwarden
```

### 2. Instalar dependencias

```bash
./scripts/install.sh
```

> 📘 Cuando pregunte si configurar el cron, responde **"n"** (lo haremos después de crear la cuenta).

### 3. Levantar Vaultwarden

```bash
./scripts/start.sh
```

### 4. Configurar Cloudflare Tunnel

En el panel de **Cloudflare Zero Trust** → **Tunnels** → tu tunnel → **Public Hostname**:

| Campo     | Valor                   |
| :-------- | :---------------------- |
| Subdomain | `vaultwarden`           |
| Domain    | `herwingx.dev`          |
| Service   | `http://vaultwarden:80` |

> ⚠️ **Importante**: Usa `http://vaultwarden:80` (nombre del contenedor), no `localhost`.

### 5. Crear tu cuenta

Accede a **https://vaultwarden.herwingx.dev** y crea tu cuenta.

### 6. Obtener API Keys

1. Ve a **⚙️ Ajustes** → **Seguridad** → **Keys**
2. Click en **Ver API Key**
3. Copia el `client_id` y `client_secret`

### 7. Actualizar secretos con tus API Keys

```bash
./scripts/manage_secrets.sh edit
```

Completa los valores:

```env
BW_CLIENTID=user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
BW_CLIENTSECRET=el_secret_que_copiaste
BW_PASSWORD=tu_contraseña_maestra
```

### 8. Cerrar registros

Edita `docker-compose.yml`:

```yaml
- SIGNUPS_ALLOWED=false
```

Reinicia:

```bash
docker compose down && ./scripts/start.sh
```

### 9. Configurar backups automáticos

Ahora que tienes las API Keys configuradas:

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
BW_HOST=https://vaultwarden.herwingx.dev
BW_CLIENTID=user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
BW_CLIENTSECRET=tu_client_secret
BW_PASSWORD=tu_contraseña_maestra

# Telegram (Bot @BotFather, ID con @userinfobot)
TELEGRAM_TOKEN=123456:ABC-token
TELEGRAM_CHAT_ID=123456789

# Rclone
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

Edita el crontab:

```bash
crontab -e
```

Añade esta línea para backup diario a las 3:00 AM:

```bash
0 3 * * * AGE_PASSPHRASE="tu_passphrase_aqui" /opt/vaultwarden/scripts/backup.sh >> /var/log/vw_backup.log 2>&1
```

> 📘 **Nota**: La variable `AGE_PASSPHRASE` permite la ejecución sin interacción.

---

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTERNET                                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                    ┌───────▼───────┐
                    │  Cloudflare   │
                    │    Tunnel     │
                    └───────┬───────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                      PROXMOX LXC                                │
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
│  │  backup.sh   │──│  AGE Cipher  │──│  rclone → G.Drive    │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📁 Estructura del Proyecto

```
vaultwarden-proxmox/
├── docker-compose.yml       # Configuración de Vaultwarden + Cloudflared
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
# Instalación completa (dependencias + cron)
./scripts/install.sh

# Levantar servicio
./scripts/start.sh

# Ver logs
docker compose logs -f

# Reiniciar después de cambios
docker compose down && ./scripts/start.sh

# Gestión de secretos
./scripts/manage_secrets.sh encrypt    # Cifrar .env
./scripts/manage_secrets.sh decrypt    # Descifrar a .env
./scripts/manage_secrets.sh edit       # Editar y re-cifrar
./scripts/manage_secrets.sh view       # Ver sin guardar

# Backup manual
./scripts/backup.sh
```

---

## 📚 Documentación

| Documento                                                                                           | Descripción                |
| :-------------------------------------------------------------------------------------------------- | :------------------------- |
| [Vaultwarden Wiki](https://github.com/dani-garcia/vaultwarden/wiki)                                 | Documentación oficial      |
| [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) | Configuración de túneles   |
| [AGE Encryption](https://age-encryption.org/)                                                       | Cifrado moderno            |
| [Rclone Docs](https://rclone.org/docs/)                                                             | Sincronización con la nube |

---

## 🛠️ Stack Tecnológico

**Servidor**
- **Vaultwarden**: Servidor compatible con Bitwarden (Rust)
- **Docker**: Contenedorización

**Seguridad**
- **Cloudflare Tunnel**: Exposición segura sin puertos abiertos
- **AGE**: Cifrado de secretos y backups

**Backup**
- **Bitwarden CLI**: Exportación de bóveda
- **Rclone**: Sincronización con Google Drive
- **Telegram Bot API**: Notificaciones

---

## 🔒 Seguridad

- ✅ Sin puertos abiertos en el router (Cloudflare Tunnel)
- ✅ Secretos cifrados con AGE + passphrase
- ✅ Backups cifrados antes de subir a la nube
- ✅ Archivos sensibles excluidos de Git
- ✅ Registro deshabilitado después de crear cuenta
- ✅ Soporte para 2FA/TOTP

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
