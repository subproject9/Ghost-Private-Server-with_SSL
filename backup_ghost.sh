#!/bin/bash
#
# A simple script to back up the Ghost database and content files.
#

### --- Configure Here --- ###
# Set this to your Ghost installation directory (the one from the main script).
GHOST_INSTALL_DIR="/var/www/blog.yourdomain.com"

# Set the directory where you want to store backups.
BACKUP_DIR="/var/backups/ghost"

# Set how many days to keep backups.
RETENTION_DAYS=14
### --- End Configuration --- ###


# --- Main Logic ---
echo "Starting Ghost backup..."

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Get database name from Ghost's config file
# This avoids hardcoding the DB name.
DB_NAME=$(grep -oP '(?<="database": ")[^"]*' "$GHOST_INSTALL_DIR/config.production.json")

if [ -z "$DB_NAME" ]; then
    echo "ERROR: Could not find database name in Ghost config. Exiting."
    exit 1
fi

DATE=$(date +"%Y-%m-%d_%H%M")

# 1. Back up the database using mysqldump
echo "Backing up database: $DB_NAME"
mysqldump --single-transaction "$DB_NAME" > "$BACKUP_DIR/db-backup-$DATE.sql"

# 2. Back up the content directory (images, themes, etc.)
echo "Backing up content files..."
tar -czf "$BACKUP_DIR/content-backup-$DATE.tar.gz" -C "$GHOST_INSTALL_DIR" content

# 3. Clean up old backups based on retention policy
echo "Cleaning up old backups..."
find "$BACKUP_DIR" -type f -name "*.sql" -mtime +"$RETENTION_DAYS" -exec rm {} \;
find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +"$RETENTION_DAYS" -exec rm {} \;

echo "✅ Backup complete!"
