#!/usr/bin/env bash
set -e

# change according to alpine and php release
PHP_VERSION=81

# Display PHP error's or not
if [[ "$ERRORS" != "1" ]] ; then
  sed -i -e "s/error_reporting =.*/error_reporting = E_ALL/g" /etc/php${PHP_VERSION}/php.ini
  sed -i -e "s/display_errors =.*/display_errors = stdout/g" /etc/php${PHP_VERSION}/php.ini
fi

# Disable opcache?
if [[ -n "${NO_OPCACHE:-}" ]]; then
  sed -i -e "s/^zend_extension=opcache.so/;zend_extension=opcache.so/g" \
    /etc/php${PHP_VERSION}/conf.d/00_opcache.ini
fi

# Tweak nginx to match the workers to CPU cores
procs=$(grep -c ^processor /proc/cpuinfo)
sed -i -e "s/worker_processes .*/worker_processes $procs;/" /etc/nginx/nginx.conf

# Copy important env vars for PHP-FPM to access
PHP_ENV_FILE="/etc/php${PHP_VERSION}/php-fpm.d/${PHP_ENV_FILE:-env.conf}"
{
  echo '[www]'
  echo 'user = nginx'
  echo 'group = www-data'
  echo 'listen.owner = nginx'
  echo 'listen.group = www-data'
} > "$PHP_ENV_FILE"

env | grep -E \
  'REPORT_DB_TYPE|REPORT_DB_HOST|REPORT_DB_PORT|REPORT_DB_NAME|REPORT_DB_USER|REPORT_DB_PASS' \
  | sed "s/\(.*\)=\(.*\)/env[\1] = '\2'/" >> "$PHP_ENV_FILE"

# Compat from older image where variable was not existing
grep -q '^env\[REPORT_DB_PORT\]' "$PHP_ENV_FILE" \
  || echo "env[REPORT_DB_PORT] = 3306" >> "$PHP_ENV_FILE"

# Get and parse dmarc reports once at startup
if /usr/bin/dmarcts-report-parser.pl -i -d -r \
  > /var/log/nginx/dmarc-reports.log 2>&1; then
  echo 'INFO: Dmarc reports parsed successfully'
else
  echo 'CRIT: Dmarc reports could not be parsed. Check your IMAP and MYSQL settings.'
  echo -e "DEBUG output:\n"
  cat /var/log/nginx/dmarc-reports.log
  exit 1
fi

# Disable nginx IPv6 listener if requested
if [[ -n "${NO_NGINX_IPV6:-}" ]]; then
  echo "[entrypoint] NO_NGINX_IPV6 is set — disabling nginx IPv6 listeners"
  sed -i \
    -e 's/^[[:space:]]*\(listen[[:space:]]\+\[::\]:[0-9]\+[[:space:]]\+default_server;\)/# \1/' \
    /etc/nginx/nginx.conf
fi

# Start supervisord and services
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
