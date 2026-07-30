#!/bin/sh
set -e

# Install openssl if missing (nginx:alpine doesn't ship it)
if ! command -v openssl >/dev/null 2>&1; then
    echo "Installing openssl..."
    apk add --no-cache openssl >/dev/null 2>&1 || { echo "Failed to install openssl"; exit 1; }
    echo "openssl installed"
fi

# Generate self-signed placeholder certificates for any domain that lacks real ones.
DOMAINS="bbsmc.org.cn api.bbsmc.org.cn cdn.bbsmc.org.cn admin.bbsmc.org.cn launcher-meta.bbsmc.org.cn www.bbsmc.org.cn"

for domain in $DOMAINS; do
    cert_dir="/etc/nginx/ssl/$domain"
    cert_file="$cert_dir/fullchain.pem"
    key_file="$cert_dir/privkey.pem"

    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        echo "Generating self-signed certificate for $domain..."
        mkdir -p "$cert_dir"
        openssl ecparam -genkey -name prime256v1 -out "$key_file"
        openssl req -new -x509 -days 365 \
            -key "$key_file" \
            -out "$cert_file" \
            -subj "/CN=$domain/O=Self-Signed/OU=Development"
        echo "Done: $domain"
    fi
done

exec nginx -g "daemon off;"
