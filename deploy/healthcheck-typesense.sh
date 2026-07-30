#!/bin/sh
wget -q -O - http://127.0.0.1:8108/health 2>/dev/null | grep -q '"ok"'