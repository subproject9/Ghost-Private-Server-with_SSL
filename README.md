# Ghost-Private-Server-with_SSL
Script installs and configures SSL using Cloudflare DNS verification on Ubuntu 24.04

# Ghost Blog Installation & Backup Scripts for Ubuntu

This repository contains a set of scripts to automate the installation and backup of a Ghost blog on an Ubuntu 24.04 server. The installation script is designed for a server that is not publicly accessible and uses Cloudflare's DNS for Let's Encrypt SSL certificate verification.

It follows security best practices by creating a non-root user for Ghost, hardening the MySQL database, and configuring a UFW firewall.

## Features

* **Automated Ghost Installation**: Installs Ghost, Nginx, and MySQL.
* **Secure SSL**: Uses Certbot with the Cloudflare DNS-01 challenge to get a valid SSL certificate without exposing the server to the internet.
* **System Hardening**: Configures the UFW firewall and runs a basic MySQL hardening script.
* **Automated Backups**: Includes a separate script to back up your Ghost database and content files.
* **User-Friendly**: The installation script prompts for all necessary information.

---

## 1. Prerequisites

Before you begin, ensure you have the following:

1.  **An Ubuntu 24.04 Server**: A clean installation is recommended.
2.  **A Domain Name**: You need a registered domain name managed through Cloudflare.
3.  **A Cloudflare Account**: Your domain's DNS must be managed by Cloudflare.
4.  **A Cloudflare API Token**: The script needs an API token to create the DNS records required for SSL verification.
    * Go to your Cloudflare Dashboard -> **My Profile** -> **API Tokens**.
    * Click **Create Token**.
    * Find the **Edit zone DNS** template and click **Use template**.
    * Under **Zone Resources**, select the specific domain you'll use for your blog.
    * Click **Continue to summary**, then **Create Token**.
    * **Important**: Copy the generated token immediately. You will not be able to see it again.

---

## 2. Installation Instructions (`install_ghost.sh`)

This script will install and configure your Ghost blog.

### Steps:

1.  **Clone the Repository**
    Clone this repository to your Ubuntu server:
    ```bash
    git clone https://github.com/subproject9/Ghost-Private-Server-with_SSL
    cd Ghost-Private-Server-with_SSL
    ```

2.  **Make the Script Executable**
    ```bash
    chmod +x install_ghost.sh
    ```

3.  **Run the Script**
    Run the script with `sudo`. It needs root privileges to install packages and configure system services.
    ```bash
    sudo ./install_ghost.sh
    ```

4.  **Follow the Prompts**
    The script will ask you for:
    * Your blog's domain name (e.g., `blog.yourdomain.com`).
    * Your email address (for SSL certificate renewal notices).
    * Your Cloudflare API Token (paste it when prompted).

The script will handle the rest. Once it's finished, it will display the URL for your blog and your Ghost admin panel.

---

## 3. Backup & Restore Instructions (`backup_ghost.sh`)

It is critical to have regular backups of your site. This script backs up your Ghost database and your `content` directory (which contains themes, images, etc.).

### Setup Steps:

1.  **Configure the Script**
    Open the `backup_ghost.sh` script and edit the configuration section at the top:
    ```bash
    # Set this to your Ghost installation directory (the one from the main script).
    GHOST_INSTALL_DIR="/var/www/blog.yourdomain.com" # <-- CHANGE THIS
    
    # Set the directory where you want to store backups.
    BACKUP_DIR="/var/backups/ghost"
    
    # Set how many days to keep backups.
    RETENTION_DAYS=14
    ```
    **Make sure you change `GHOST_INSTALL_DIR` to match your domain.**

2.  **Move the Script to a System Directory**
    Place the script in a standard location for system binaries.
    ```bash
    sudo mv backup_ghost.sh /usr/local/bin/backup_ghost.sh
    ```

3.  **Make it Executable**
    ```bash
    sudo chmod +x /usr/local/bin/backup_ghost.sh
    ```

4.  **Automate with Cron**
    Set up a cron job to run the backup script automatically.
    * Open the root crontab editor:
        ```bash
        sudo crontab -e
        ```
    * Add the following line to the file. This will run the backup every day at 3:00 AM.
        ```crontab
        0 3 * * * /usr/local/bin/backup_ghost.sh > /dev/null 2>&1
        ```
    * Save and exit the editor. Your backups are now automated!

### Restoring from a Backup

To restore your site, you would:
1.  Install a fresh instance of Ghost.
2.  Restore the database: `mysql -u root -p your_ghost_db < /path/to/db-backup-YYYY-MM-DD_HHMM.sql`
3.  Restore the content files: `tar -xzf /path/to/content-backup-YYYY-MM-DD_HHMM.tar.gz -C /var/www/your_domain/`

---

## 4. Post-Installation Best Practices

For the best long-term experience, consider the following steps after installation.

### Configure Transactional Email

To ensure reliable email delivery for newsletters and password resets, configure a dedicated email service like Mailgun or SendGrid.
1.  Log in as your Ghost user: `su - <your_ghost_user>`
2.  Navigate to your install directory: `cd /var/www/your_domain`
3.  Run the mail configuration tool: `ghost config mail` and follow the prompts.
4.  Restart Ghost: `ghost restart`

### System Maintenance

* **Update Ghost**: When new versions are released, you can update easily. As your Ghost user, run:
    ```bash
    ghost update
    ```
* **Update Ubuntu**: Periodically run the following commands to keep your server's packages up to date:
    ```bash
    sudo apt update
    sudo apt upgrade -y
    ````
