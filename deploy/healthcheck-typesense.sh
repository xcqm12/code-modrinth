#!/usr/bin/bash
# Health check script for typesense
# Uses bash's /dev/tcp feature to check if the typesense HTTP API is responding

# Try to open TCP connection to typesense
exec 3<>/dev/tcp/127.0.0.1/8108 || exit 1

# Send a simple HTTP GET request
printf 'GET /health HTTP/1.0\r\nHost: localhost\r\n\r\n' >&3

# Read response and check for 200 OK
grep -q '200 OK' <&3
