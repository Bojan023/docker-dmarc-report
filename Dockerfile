ARG UPSTREAM_IMAGE=trafex/php-nginx:2.6.0

FROM $UPSTREAM_IMAGE

LABEL maintainer="Robert Schumann <rs@n-os.org>"

ENV REPORT_PARSER_SOURCE="https://github.com/techsneeze/dmarcts-report-parser/archive/master.zip" \
  REPORT_VIEWER_SOURCE="https://github.com/techsneeze/dmarcts-report-viewer/archive/master.zip"

USER root

WORKDIR /

COPY ./manifest/ /

RUN set -e -x \
  && apk add -U \
  bash \
  cmake \
  expat-dev \
  g++ \
  gpg \
  gzip \
  libpq \
  libpq-dev \
  make \
  mariadb-client \
  mariadb-connector-c \
  mariadb-dev \
  musl-obstack \
  musl-obstack-dev \
  openssl \
  openssl-dev \
  perl-dev \
  perl-utils \
  perl-net-ssleay \
  perl-io-socket-ssl \
  php81-pdo \
  php81-pdo_mysql \
  php81-pdo_pgsql \
  tzdata \
  wget \
  && wget -O /tmp/cpanm https://cpanmin.us \
  && perl /tmp/cpanm --sudo App::cpanminus \
  && wget -4 -q --no-check-certificate -O parser.zip $REPORT_PARSER_SOURCE \
  && wget -4 -q --no-check-certificate -O viewer.zip $REPORT_VIEWER_SOURCE \
  && unzip parser.zip && cp -av dmarcts-report-parser-master/* /usr/bin/ && rm -vf parser.zip && rm -rvf dmarcts-report-parser-master \
  && unzip viewer.zip && cp -av dmarcts-report-viewer-master/* /var/www/viewer/ && rm -vf viewer.zip && rm -rvf dmarcts-report-viewer-master \
  && sed -i "1s/^/body { font-family: Sans-Serif; }\n/" /var/www/viewer/default.css \
  && sed -i 's%^\s*listen \[::\]:8080 default_server;%        listen [::]:80 default_server;%g' /etc/nginx/nginx.conf \
  && sed -i 's%.*listen 8080 default_server;%        listen 80 default_server;%g' /etc/nginx/nginx.conf \
  && sed -i 's%.*root /var/www/html;%        root /var/www/viewer;%g' /etc/nginx/nginx.conf \
  && sed -i 's/.*index index.php index.html;/        index dmarcts-report-viewer.php;/g' /etc/nginx/nginx.conf \
  && sed -i 's%files = /etc/supervisor.d/\*.ini%files = /etc/supervisor/conf.d/*.conf%g' /etc/supervisord.conf \
  && cpanm --notest \
    IO::Socket::SSL \
    CPAN \
    CPAN::DistnameInfo \
    File::MimeInfo \
    IO::Compress::Gzip \
    Getopt::Long \
    Mail::IMAPClient \
    Mail::Mbox::MessageParser \
    MIME::Base64 \
    MIME::Words \
    MIME::Parser \
    XML::Parser \
    XML::Simple \
    DBI \
    DBD::mysql@4.052 \
    DBD::Pg \
    Socket \
    Socket6 \
    PerlIO::gzip \
  && apk del mariadb-dev expat-dev openssl-dev perl-dev g++ cmake make musl-obstack-dev libpq-dev

HEALTHCHECK --interval=1m --timeout=3s CMD curl --silent --fail http://127.0.0.1:80/fpm-ping

EXPOSE 80

CMD ["/bin/bash", "/entrypoint.sh"]
