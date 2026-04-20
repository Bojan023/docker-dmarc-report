#!/usr/bin/env bash
set -e

###############################################################################
# Auto-detect PHP version
###############################################################################
PHP_VERSION="$(basename /etc/php*)"
PHP_INI="/etc/${PHP_VERSION}/php.ini"
PHP_CONF_DIR="/etc/${PHP_VERSION}/conf.d"
PHP_FPM_DIR="/etc/${PHP_VERSION}/php-fpm.d"
PHP_FPM_POOL="${PHP_FPM_DIR}/www.conf"

###############################################################################
# PHP error display
###############################################################################
if [[ "${ERRORS:-}" != "1" ]]; then
  sed -i "s|^error_reporting =.*|error_reporting = E_ALL|" "$PHP_INI"
  sed -i "s|^display_errors =.*|display_errors = stdout|" "$PHP_INI"
fi

###############################################################################
# OPCache toggle
###############################################################################
if [[ -n "${NO_OPCACHE:-}" ]]; then
  sed -i "s|^zend_extension=opcache.so|;zend_extension=opcache.so|" \
    "${PHP_CONF_DIR}/00_opcache.ini" || true
fi

###############################################################################
# nginx workers = CPU count
###############################################################################
procs=$(grep -c ^processor /proc/cpuinfo || echo 1)
sed -i "s|worker_processes .*;|worker_processes ${procs};|" \
  /etc/nginx/nginx.conf

###############################################################################
# Ensure PHP-FPM pool exists and has user/group ✅
###############################################################################
mkdir -p "$PHP_FPM_DIR"

if [[ ! -f "$PHP_FPM_POOL" ]]; then
  echo "[www]" > "$PHP_FPM_POOL"
fi

sed -i \
  -e 's|^;*user =.*|user = nginx|' \
  -e 's|^;*group =.*|group = www-data|' \
  "$PHP_FPM_POOL" || true

###############################################################################
# PHP-FPM environment variables
###############################################################################
PHP_ENV_FILE="${PHP_FPM_DIR}/env.conf"

{
  echo "[www]"
  echo "clear_env = no"
} > "$PHP_ENV_FILE"

env | grep -E \
  'REPORT_DB_TYPE|REPORT_DB_HOST|REPORT_DB_PORT|REPORT_DB_NAME|REPORT_DB_USER|REPORT_DB_PASS' \
  | sed "s|\(.*\)=\(.*\)|env[\1] = '\2'|" >> "$PHP_ENV_FILE"

grep -q '^env\[REPORT_DB_PORT\]' "$PHP_ENV_FILE" \
  || echo "env[REPORT_DB_PORT] = 3306" >> "$PHP_ENV_FILE"

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
# ✅ Disable nginx IPv6 EVERYWHERE (THIS IS THE KEY FIX)
###############################################################################
if [[ -n "${NO_NGINX_IPV6:-}" ]]; then
  echo "[entrypoint] NO_NGINX_IPV6 is set — disabling nginx IPv6 listeners"

  find /etc/nginx -type f -name '*.conf' -print0 \
    | xargs -0 sed -i \
      's/^[[:space:]]*listen[[:space:]]\+\[::\]:[0-9]\+.*;/# &/'
fi

###############################################################################
# Start everything
###############################################################################
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
