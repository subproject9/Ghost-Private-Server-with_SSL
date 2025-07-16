#!/bin/bash

# =============================================================================
# Ghost Blog Installation Script for Ubuntu 24.04 (Hardened)
# Secures with Let's Encrypt using Cloudflare and configures a firewall.
# =============================================================================

# --- Script Configuration ---
set -e

# --- Style Functions ---
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m"

# --- Prerequisite Check ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}Please run this script with sudo or as root.${NC}"
  exit 1
fi

# --- User Input ---
clear
echo -e "${BLUE}--- Ghost Blog & SSL Setup (Hardened) ---${NC}"
echo "This script will install Ghost and secure it with a firewall and Let's Encrypt."
echo "Please provide the following information:"
echo ""

read -p "Enter your blog's domain name (e.g., blog.yourdomain.com): " DOMAIN_NAME
read -p "Enter your email address (for Let's Encrypt notifications): " EMAIL_ADDRESS
read -sp "Paste your Cloudflare API Token: " CF_API_TOKEN
echo ""
echo ""

if [ -z "$DOMAIN_NAME" ] || [ -z "$EMAIL_ADDRESS" ] || [ -z "$CF_API_TOKEN" ]; then
  echo -e "${YELLOW}Domain name, email, and Cloudflare token are required. Aborting.${NC}"
  exit 1
fi

GHOST_INSTALL_DIR="/var/www/${DOMAIN_NAME}"

# =============================================================================
# STEP 1: SYSTEM PREPARATION & HARDENING
# =============================================================================
echo -e "\n${BLUE}Updating system packages and installing dependencies...${NC}"
apt-get update > /dev/null
apt-get upgrade -y > /dev/null
apt-get install -y nginx curl mysql-server software-properties-common > /dev/null

echo -e "${BLUE}Hardening MySQL installation... (Non-interactive)${NC}"
# This performs the key hardening steps of mysql_secure_installation.
mysql -e "DELETE FROM mysql.user WHERE User=''; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'; FLUSH PRIVILEGES;" > /dev/null

echo -e "${BLUE}Configuring firewall (UFW) to allow SSH and Web traffic...${NC}"
ufw allow ssh > /dev/null
ufw allow 'Nginx Full' > /dev/null
# Enable UFW non-interactively
echo "y" | ufw enable > /dev/null

# =============================================================================
# STEP 2: INSTALL NODE.JS, NPM & GHOST-CLI
# =============================================================================
echo -e "${BLUE}Installing Node.js, npm, and Ghost-CLI...${NC}"
# Ubuntu 24.04 ships with Node.js v20, which is supported by Ghost.
apt-get install -y nodejs npm > /dev/null
npm install ghost-cli@latest -g > /dev/null

# =============================================================================
# STEP 3: INSTALL GHOST (WITHOUT SSL)
# =============================================================================
echo -e "${BLUE}Setting up Ghost installation directory...${NC}"
mkdir -p "$GHOST_INSTALL_DIR"
chown $SUDO_USER:$SUDO_USER "$GHOST_INSTALL_DIR"
chmod 775 "$GHOST_INSTALL_DIR"

echo -e "${YELLOW}Now running the Ghost installer.${NC}"
echo -e "${YELLOW}When prompted, provide your MySQL root password to set up the database.${NC}"
sleep 3

# Install Ghost, letting it set up MySQL and Nginx, but skipping SSL for now.
# We run this as the original user to avoid permission issues.
su - "$SUDO_USER" -c "cd $GHOST_INSTALL_DIR && ghost install \
--url \"https://${DOMAIN_NAME}\" \
--db mysql \
--process systemd \
--stack \
--no-setup-ssl"

# =============================================================================
# STEP 4: OBTAIN SSL CERTIFICATE WITH CERTBOT & CLOUDFLARE
# =============================================================================
echo -e "\n${BLUE}Installing Certbot with the Cloudflare DNS plugin...${NC}"
apt-get install -y certbot python3-certbot-dns-cloudflare > /dev/null

echo -e "${BLUE}Creating Cloudflare credentials file for Certbot...${NC}"
mkdir -p /etc/letsencrypt/
cat <<EOF > /etc/letsencrypt/cloudflare.ini
# Cloudflare API token used by Certbot
dns_cloudflare_api_token = ${CF_API_TOKEN}
EOF
chmod 600 /etc/letsencrypt/cloudflare.ini

echo -e "${BLUE}Requesting SSL certificate from Let's Encrypt... (This may take a minute)${NC}"
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL_ADDRESS" \
  -d "$DOMAIN_NAME"

# =============================================================================
# STEP 5: CONFIGURE NGINX FOR SSL & FINALIZE
# =============================================================================
echo -e "\n${BLUE}Configuring Nginx to use the new SSL certificate...${NC}"

# Find the SSL certificate and key paths
CERT_PATH="/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem"

if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    echo -e "${YELLOW}Certbot failed to obtain certificates. Please check for errors above. Aborting.${NC}"
    exit 1
fi

# Use ghost-cli to configure SSL
su - "$SUDO_USER" -c "cd $GHOST_INSTALL_DIR && ghost setup nginx ssl --cert \"$CERT_PATH\" --key \"$KEY_PATH\""

echo -e "${BLUE}Restarting Ghost to apply all changes...${NC}"
su - "$SUDO_USER" -c "cd $GHOST_INSTALL_DIR && ghost restart"

# =============================================================================
# INSTALLATION COMPLETE
# =============================================================================
clear
echo -e "${GREEN}✅ Success! Ghost has been installed and secured.${NC}"
echo ""
echo "---------------------------------------------------------"
echo -e "Your blog is now running at: ${YELLOW}https://"$DOMAIN_NAME"${NC}"
echo -e "Access your Ghost admin panel at: ${YELLOW}https://"$DOMAIN_NAME"/ghost/${NC}"
echo -e "The UFW firewall is active and your MySQL installation is hardened."
echo "---------------------------------------------------------"
echo ""
echo "Certbot has been configured to renew your SSL certificate automatically."
echo "Enjoy your new Ghost blog! 🎉"
