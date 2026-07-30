#!/bin/sh
set -e

# Generate self-signed placeholder certificates for any domain that lacks real ones.
# This allows nginx to start even before real SSL certs are placed.
DOMAINS="bbsmc.org.cn api.bbsmc.org.cn cdn.bbsmc.org.cn admin.bbsmc.org.cn launcher-meta.bbsmc.org.cn www.bbsmc.org.cn"

for domain in $DOMAINS; do
    cert_dir="/etc/nginx/ssl/$domain"
    cert_file="$cert_dir/fullchain.pem"
    key_file="$cert_dir/privkey.pem"

    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        echo "Generating self-signed certificate for $domain..."
        mkdir -p "$cert_dir"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$key_file" \
            -out "$cert_file" \
            -subj "/CN=$domain/O=Self-Signed/OU=Development" \
            2>/dev/null
    fi
done

exec nginx -g "daemon off;"
