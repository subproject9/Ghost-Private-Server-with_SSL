#!/bin/bash

# =============================================================================
# Ghost Blog Installation Script for Ubuntu 24.04 (Hardened)
# Secures with Let's Encrypt using Cloudflare and configures a firewall.
# Features animated progress indicators for a better user experience.
# =============================================================================

# --- Script Configuration ---
set -e

# --- Style Functions ---
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m"

# --- Animated Spinner Function ---
# Shows an animated spinner while a command runs in the background.
# Replaces spinner with a checkmark or cross upon completion.
# Usage: run_with_spinner "Doing something..." "command_to_run"
run_with_spinner() {
    local msg="$1"
    local cmd="$2"
    local spin='|/-\'
    local log_file="/tmp/spinner.log"

    echo -n -e "$msg"

    # Run command in the background and redirect its output to a log file.
    eval "$cmd" &> "$log_file" &
    local pid=$!

    # Show spinner animation
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        echo -n -e "\r${BLUE}${msg} [${spin:$i:1}]${NC}"
        sleep 0.1
    done

    # Wait for the command to finish and get its exit code.
    wait $pid
    local exit_code=$?

    # Check the exit code and display the final status.
    if [ $exit_code -eq 0 ]; then
        echo -e "\r${GREEN}${msg} [✓]${NC}"
    else
        echo -e "\r${YELLOW}${msg} [✗]${NC}"
        echo -e "${YELLOW}Error during: '$cmd' (See log below)${NC}"
        echo "--- Log Output ---"
        cat "$log_file"
        echo "------------------"
        rm -f "$log_file"
        exit 1
    fi
    rm -f "$log_file"
}


# --- Prerequisite Check ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}Please run this script with sudo or as root.${NC}"
  exit 1
fi

# --- User Input ---
clear

# --- ASCII Art Welcome ---
cat << "EOF"
 ______________
|[]           |
|  __________  |
|  | Ghost  |  |
|  | Blog   |  |
|  |________|  |
|   ________   |
|   [ [ ]  ]   |
\___[_[_]__]___|
subproject9.com
EOF

echo -e "\n${BLUE}--- Ghost Blog & SSL Setup (Hardened) ---${NC}"
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
echo -e "\n${BLUE}--- Preparing System ---${NC}"
run_with_spinner "Updating system packages..." "apt-get update"
run_with_spinner "Upgrading system packages..." "apt-get upgrade -y"
run_with_spinner "Installing dependencies (Nginx, MySQL, etc.)..." "apt-get install -y nginx curl mysql-server software-properties-common"

# --- Interactive MySQL Hardening ---
echo -e "\n${YELLOW}--- Securing MySQL Installation ---${NC}"
echo "You will now be prompted to secure your MySQL installation."
echo "It is highly recommended to set a root password."
echo "Press 'Y' for the 'VALIDATE PASSWORD component'."
echo "Choose a password strength (e.g., 2 for strong)."
echo -e "Remember the password you set. You will need it in the next step.${NC}"
sleep 5
sudo mysql_secure_installation

run_with_spinner "Configuring firewall (UFW)..." "ufw allow ssh > /dev/null && ufw allow 'Nginx Full' > /dev/null && echo 'y' | ufw enable > /dev/null"

# =============================================================================
# STEP 2: INSTALL NODE.JS, NPM & GHOST-CLI
# =============================================================================
echo -e "\n${BLUE}--- Installing Ghost-CLI and Dependencies ---${NC}"
run_with_spinner "Installing Node.js and npm..." "apt-get install -y nodejs npm"
run_with_spinner "Installing Ghost-CLI (this may take a moment)..." "npm install ghost-cli@latest -g"

# =============================================================================
# STEP 3: INSTALL GHOST (WITHOUT SSL)
# =============================================================================
echo -e "\n${BLUE}--- Installing Ghost ---${NC}"
run_with_spinner "Creating Ghost installation directory..." "mkdir -p $GHOST_INSTALL_DIR && chown $SUDO_USER:$SUDO_USER $GHOST_INSTALL_DIR && chmod 775 $GHOST_INSTALL_DIR"

echo -e "${YELLOW}Now running the interactive Ghost installer...${NC}"
echo -e "${YELLOW}When prompted, enter the MySQL root password you just created.${NC}"
sleep 3

# The Ghost installer is interactive and provides its own progress, so we run it directly.
su - "$SUDO_USER" -c "cd $GHOST_INSTALL_DIR && ghost install \
--url \"https://${DOMAIN_NAME}\" \
--db mysql \
--process systemd \
--stack \
--no-setup-ssl"

# =============================================================================
# STEP 4: OBTAIN SSL CERTIFICATE WITH CERTBOT & CLOUDFLARE
# =============================================================================
echo -e "\n${BLUE}--- Configuring SSL Certificate ---${NC}"
run_with_spinner "Installing Certbot with Cloudflare plugin..." "apt-get install -y certbot python3-certbot-dns-cloudflare"
run_with_spinner "Creating Cloudflare credentials file..." "mkdir -p /etc/letsencrypt/ && echo 'dns_cloudflare_api_token = ${CF_API_TOKEN}' > /etc/letsencrypt/cloudflare.ini && chmod 600 /etc/letsencrypt/cloudflare.ini"
run_with_spinner "Requesting SSL certificate from Let's Encrypt..." "certbot certonly --dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini --non-interactive --agree-tos --email \"$EMAIL_ADDRESS\" -d \"$DOMAIN_NAME\""

# =============================================================================
# STEP 5: CONFIGURE NGINX FOR SSL & FINALIZE
# =============================================================================
echo -e "\n${BLUE}--- Finalizing Setup ---${NC}"
CERT_PATH="/etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem"

if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    echo -e "${YELLOW}Certbot failed to obtain certificates. Please check logs above. Aborting.${NC}"
    exit 1
fi

# Ghost's setup commands are also interactive/verbose.
echo -e "${BLUE}Configuring Nginx to use the new SSL certificate...${NC}"
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
