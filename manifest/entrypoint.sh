#!/usr/bin/env bash
set -e

###############################################################################
# Auto-detect installed PHP version (php81, php82, php83, …)
###############################################################################
PHP_VERSION="$(basename /etc/php*)"
PHP_INI="/etc/${PHP_VERSION}/php.ini"
PHP_CONF_DIR="/etc/${PHP_VERSION}/conf.d"
PHP_FPM_DIR="/etc/${PHP_VERSION}/php-fpm.d"

###############################################################################
# Display PHP errors or not
###############################################################################
if [[ "${ERRORS:-}" != "1" ]]; then
  sed -i -e "s/^error_reporting =.*/error_reporting = E_ALL/" "$PHP_INI"
  sed -i -e "s/^display_errors =.*/display_errors = stdout/" "$PHP_INI"
fi

###############################################################################
# Disable opcache if requested
###############################################################################
if [[ -n "${NO_OPCACHE:-}" ]]; then
  sed -i -e "s/^zend_extension=opcache.so/;zend_extension=opcache.so/" \
    "${PHP_CONF_DIR}/00_opcache.ini"
fi

###############################################################################
# Tweak nginx workers to match CPU cores
###############################################################################
procs=$(grep -c ^processor /proc/cpuinfo)
sed -i -e "s/worker_processes .*/worker_processes $procs;/" /etc/nginx/nginx.conf

###############################################################################
# Prepare PHP-FPM env configuration (FIXED)
###############################################################################
mkdir -p "$PHP_FPM_DIR"
PHP_ENV_FILE="${PHP_FPM_DIR}/${PHP_ENV_FILE:-env.conf}"

{
  echo "[www]"
  echo "user = nginx"
  echo "group = www-data"
  echo "listen.owner = nginx"
  echo "listen.group = www-data"
} > "$PHP_ENV_FILE"

env | grep -E \
  'REPORT_DB_TYPE|REPORT_DB_HOST|REPORT_DB_PORT|REPORT_DB_NAME|REPORT_DB_USER|REPORT_DB_PASS' \
  | sed "s/\(.*\)=\(.*\)/env[\1] = '\2'/" >> "$PHP_ENV_FILE"

# Compatibility with older images
grep -q '^env\[REPORT_DB_PORT\]' "$PHP_ENV_FILE" \
  || echo "env[REPORT_DB_PORT] = 3306" >> "$PHP_ENV_FILE"

###############################################################################
# Parse DMARC reports once at startup
###############################################################################
if /usr/bin/dmarcts-report-parser.pl -i -d -r \
  > /var/log/nginx/dmarc-reports.log 2>&1; then
  echo "INFO: DMARC reports parsed successfully"
else
  echo "CRIT: DMARC reports could not be parsed. Check IMAP and database settings."
  echo -e "DEBUG output:\n"
  cat /var/log/nginx/dmarc-reports.log
  exit 1
fi

###############################################################################
# Optionally disable nginx IPv6 listener
###############################################################################
if [[ -n "${NO_NGINX_IPV6:-}" ]]; then
  echo "[entrypoint] NO_NGINX_IPV6 is set — disabling nginx IPv6 listeners"
  sed -i \
    -e 's/^[[:space:]]*listen[[:space:]]\+\[::\]:[0-9]\+[[:space:]]\+default_server;/# &/' \
    /etc/nginx/nginx.conf
fi

###############################################################################
# Start supervisord and managed services
###############################################################################
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
