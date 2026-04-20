#!/usr/bin/env bash
set -e

###############################################################################
# Auto-detect installed PHP version
###############################################################################
PHP_VERSION="$(basename /etc/php*)"
PHP_INI="/etc/${PHP_VERSION}/php.ini"
PHP_CONF_DIR="/etc/${PHP_VERSION}/conf.d"
PHP_FPM_DIR="/etc/${PHP_VERSION}/php-fpm.d"

###############################################################################
# Configure PHP error display
###############################################################################
if [[ "${ERRORS:-}" != "1" ]]; then
  sed -i 's|^error_reporting =.*|error_reporting = E_ALL|' "$PHP_INI"
  sed -i 's|^display_errors =.*|display_errors = stdout|' "$PHP_INI"
fi

###############################################################################
# Disable OPCache if requested
###############################################################################
if [[ -n "${NO_OPCACHE:-}" ]]; then
  sed -i 's|^zend_extension=opcache.so|;zend_extension=opcache.so|' \
    "${PHP_CONF_DIR}/00_opcache.ini" || true
fi

###############################################################################
# Tune nginx workers
###############################################################################
procs=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
sed -i "s|worker_processes .*;|worker_processes ${procs};|" \
  /etc/nginx/nginx.conf

###############################################################################
# PHP-FPM pool user override
###############################################################################
mkdir -p "$PHP_FPM_DIR"

cat > "${PHP_FPM_DIR}/zz-user.conf" <<'EOF'
[www]
user = nginx
group = www-data
clear_env = no
EOF

###############################################################################
# PHP-FPM environment variables
###############################################################################
cat > "${PHP_FPM_DIR}/env.conf" <<'EOF'
[www]
clear_env = no
EOF

env | grep -E \
  'REPORT_DB_TYPE|REPORT_DB_HOST|REPORT_DB_PORT|REPORT_DB_NAME|REPORT_DB_USER|REPORT_DB_PASS' \
  | sed "s|\(.*\)=\(.*\)|env[\1] = '\2'|" >> "${PHP_FPM_DIR}/env.conf"

grep -q '^env\[REPORT_DB_PORT\]' "${PHP_FPM_DIR}/env.conf" \
  || echo "env[REPORT_DB_PORT] = 3306" >> "${PHP_FPM_DIR}/env.conf"

###############################################################################
# Initial DMARC parse
###############################################################################
if /usr/bin/dmarcts-report-parser.pl -i -d -r \
  > /var/log/nginx/dmarc-reports.log 2>&1; then
  echo "INFO: DMARC reports parsed successfully"
else
  echo "CRIT: DMARC parsing failed"
  cat /var/log/nginx/dmarc-reports.log
  exit 1
fi

###############################################################################
# Disable nginx IPv6 listeners globally
###############################################################################
if [[ -n "${NO_NGINX_IPV6:-}" ]]; then
  echo "[entrypoint] NO_NGINX_IPV6 is set — disabling nginx IPv6 listeners"
  find /etc/nginx -type f -name '*.conf' -print0 \
    | xargs -0 sed -i \
      's/^[[:space:]]*listen[[:space:]]\+\[::\]:[0-9]\+.*;/# &/'
fi

###############################################################################
# Fix nginx root and index for DMARC viewer
###############################################################################
sed -i \
  -e 's|root\s\+/var/www/html;|root /var/www/viewer;|' \
  -e 's|index\s\+.*;|index dmarcts-report-viewer.php index.php index.html;|' \
  /etc/nginx/conf.d/default.conf

###############################################################################
# Start supervisor
###############################################################################
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
