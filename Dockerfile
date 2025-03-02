FROM php:8.3-fpm-alpine

# Install dependencies
RUN apk add --no-cache \
    nginx \
    mariadb-client \
    supervisor \
    curl \
    tar \
    unzip \
    git \
    redis \
    icu-dev \
    oniguruma-dev \
    libpng-dev \
    libxml2-dev \
    libzip-dev \
    coreutils \
    ca-certificates \
    && docker-php-ext-install pdo_mysql \
    && docker-php-ext-install bcmath \
    && docker-php-ext-install mbstring \
    && docker-php-ext-install gd \
    && docker-php-ext-install opcache \
    && docker-php-ext-install intl \
    && docker-php-ext-install xml \
    && docker-php-ext-install zip

# Configure PHP
RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini \
    && { \
    echo 'memory_limit=256M'; \
    echo 'upload_max_filesize=100M'; \
    echo 'post_max_size=100M'; \
    echo 'max_execution_time=300'; \
    } > /usr/local/etc/php/conf.d/pterodactyl.ini

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Create directory structure
RUN mkdir -p /var/www/pterodactyl \
    && mkdir -p /var/log/pterodactyl \
    && mkdir -p /etc/pterodactyl \
    && mkdir -p /etc/nginx/http.d \
    && mkdir -p /run/nginx

# Set working directory
WORKDIR /var/www/pterodactyl

# Download and configure Pterodactyl
RUN curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz \
    && tar -xzvf panel.tar.gz \
    && rm panel.tar.gz \
    && chmod -R 755 storage/* bootstrap/cache/ \
    && cp .env.example .env

# Create entrypoint script
RUN echo '#!/bin/sh' > /entrypoint.sh \
    && echo 'set -e' >> /entrypoint.sh \
    && echo '' >> /entrypoint.sh \
    && echo '# Generate app key if needed' >> /entrypoint.sh \
    && echo 'if [ -z "$(grep "^APP_KEY=" .env | grep -v "APP_KEY=$")" ]; then' >> /entrypoint.sh \
    && echo '    php artisan key:generate --force' >> /entrypoint.sh \
    && echo 'fi' >> /entrypoint.sh \
    && echo '' >> /entrypoint.sh \
    && echo '# Set up environment' >> /entrypoint.sh \
    && echo 'if [ "$DB_PORT" = "" ]; then DB_PORT=3306; fi' >> /entrypoint.sh \
    && echo 'if [ "$CACHE_DRIVER" = "" ]; then CACHE_DRIVER=redis; fi' >> /entrypoint.sh \
    && echo 'if [ "$SESSION_DRIVER" = "" ]; then SESSION_DRIVER=redis; fi' >> /entrypoint.sh \
    && echo 'if [ "$QUEUE_DRIVER" = "" ]; then QUEUE_DRIVER=redis; fi' >> /entrypoint.sh \
    && echo 'if [ "$REDIS_PORT" = "" ]; then REDIS_PORT=6379; fi' >> /entrypoint.sh \
    && echo '' >> /entrypoint.sh \
    && echo '# Update environment config' >> /entrypoint.sh \
    && echo 'sed -i "s|^APP_URL=.*|APP_URL=$APP_URL|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^APP_TIMEZONE=.*|APP_TIMEZONE=$APP_TIMEZONE|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^DB_HOST=.*|DB_HOST=$DB_HOST|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^DB_PORT=.*|DB_PORT=$DB_PORT|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$DB_DATABASE|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^DB_USERNAME=.*|DB_USERNAME=$DB_USERNAME|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$DB_PASSWORD|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^CACHE_DRIVER=.*|CACHE_DRIVER=$CACHE_DRIVER|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^SESSION_DRIVER=.*|SESSION_DRIVER=$SESSION_DRIVER|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^QUEUE_DRIVER=.*|QUEUE_DRIVER=$QUEUE_DRIVER|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^REDIS_HOST=.*|REDIS_HOST=$REDIS_HOST|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$REDIS_PASSWORD|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^REDIS_PORT=.*|REDIS_PORT=$REDIS_PORT|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^MAIL_DRIVER=.*|MAIL_DRIVER=$MAIL_DRIVER|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^MAIL_HOST=.*|MAIL_HOST=$MAIL_HOST|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^MAIL_PORT=.*|MAIL_PORT=$MAIL_PORT|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^MAIL_USERNAME=.*|MAIL_USERNAME=$MAIL_USERNAME|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^MAIL_PASSWORD=.*|MAIL_PASSWORD=$MAIL_PASSWORD|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^MAIL_ENCRYPTION=.*|MAIL_ENCRYPTION=$MAIL_ENCRYPTION|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^MAIL_FROM_ADDRESS=.*|MAIL_FROM_ADDRESS=$MAIL_FROM_ADDRESS|g" .env' >> /entrypoint.sh \
    && echo 'sed -i "s|^MAIL_FROM_NAME=.*|MAIL_FROM_NAME=$MAIL_FROM_NAME|g" .env' >> /entrypoint.sh \
    && echo '' >> /entrypoint.sh \
    && echo '# Wait for database' >> /entrypoint.sh \
    && echo 'echo "Waiting for database..."' >> /entrypoint.sh \
    && echo 'until mysql -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1"; do' >> /entrypoint.sh \
    && echo '  sleep 1' >> /entrypoint.sh \
    && echo 'done' >> /entrypoint.sh \
    && echo '' >> /entrypoint.sh \
    && echo '# Run migrations and create admin user if needed' >> /entrypoint.sh \
    && echo 'php artisan migrate --force' >> /entrypoint.sh \
    && echo 'if [ "$ADMIN_USER_SETUP" = "true" ] && [ ! -z "$ADMIN_EMAIL" ] && [ ! -z "$ADMIN_USERNAME" ] && [ ! -z "$ADMIN_FIRSTNAME" ] && [ ! -z "$ADMIN_LASTNAME" ] && [ ! -z "$ADMIN_PASSWORD" ]; then' >> /entrypoint.sh \
    && echo '    php artisan p:user:make --email="$ADMIN_EMAIL" --username="$ADMIN_USERNAME" --name-first="$ADMIN_FIRSTNAME" --name-last="$ADMIN_LASTNAME" --password="$ADMIN_PASSWORD" --admin=1 || true' >> /entrypoint.sh \
    && echo 'fi' >> /entrypoint.sh \
    && echo '' >> /entrypoint.sh \
    && echo '# Set permissions' >> /entrypoint.sh \
    && echo 'chown -R www-data:www-data /var/www/pterodactyl' >> /entrypoint.sh \
    && echo '' >> /entrypoint.sh \
    && echo '# Start supervisord' >> /entrypoint.sh \
    && echo 'exec /usr/bin/supervisord -c /etc/supervisord.conf' >> /entrypoint.sh \
    && chmod +x /entrypoint.sh

# Create NGINX configuration
RUN echo 'server {' > /etc/nginx/http.d/default.conf \
    && echo '    listen 80;' >> /etc/nginx/http.d/default.conf \
    && echo '    server_name _;' >> /etc/nginx/http.d/default.conf \
    && echo '    root /var/www/pterodactyl/public;' >> /etc/nginx/http.d/default.conf \
    && echo '    index index.php;' >> /etc/nginx/http.d/default.conf \
    && echo '    charset utf-8;' >> /etc/nginx/http.d/default.conf \
    && echo '    location / {' >> /etc/nginx/http.d/default.conf \
    && echo '        try_files $uri $uri/ /index.php?$query_string;' >> /etc/nginx/http.d/default.conf \
    && echo '    }' >> /etc/nginx/http.d/default.conf \
    && echo '    location = /favicon.ico { access_log off; log_not_found off; }' >> /etc/nginx/http.d/default.conf \
    && echo '    location = /robots.txt  { access_log off; log_not_found off; }' >> /etc/nginx/http.d/default.conf \
    && echo '    access_log /var/log/nginx/pterodactyl.access.log;' >> /etc/nginx/http.d/default.conf \
    && echo '    error_log  /var/log/nginx/pterodactyl.error.log error;' >> /etc/nginx/http.d/default.conf \
    && echo '    client_max_body_size 100m;' >> /etc/nginx/http.d/default.conf \
    && echo '    location ~ \.php$ {' >> /etc/nginx/http.d/default.conf \
    && echo '        fastcgi_split_path_info ^(.+\.php)(/.+)$;' >> /etc/nginx/http.d/default.conf \
    && echo '        fastcgi_pass 127.0.0.1:9000;' >> /etc/nginx/http.d/default.conf \
    && echo '        fastcgi_index index.php;' >> /etc/nginx/http.d/default.conf \
    && echo '        include fastcgi_params;' >> /etc/nginx/http.d/default.conf \
    && echo '        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";' >> /etc/nginx/http.d/default.conf \
    && echo '        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;' >> /etc/nginx/http.d/default.conf \
    && echo '        fastcgi_param HTTP_PROXY "";' >> /etc/nginx/http.d/default.conf \
    && echo '        fastcgi_intercept_errors off;' >> /etc/nginx/http.d/default.conf \
    && echo '        fastcgi_buffer_size 16k;' >> /etc/nginx/http.d/default.conf \
    && echo '        fastcgi_buffers 4 16k;' >> /etc/nginx/http.d/default.conf \
    && echo '    }' >> /etc/nginx/http.d/default.conf \
    && echo '    location ~ /\.ht {' >> /etc/nginx/http.d/default.conf \
    && echo '        deny all;' >> /etc/nginx/http.d/default.conf \
    && echo '    }' >> /etc/nginx/http.d/default.conf \
    && echo '}' >> /etc/nginx/http.d/default.conf

# Create Supervisor configuration
RUN echo '[supervisord]' > /etc/supervisord.conf \
    && echo 'nodaemon=true' >> /etc/supervisord.conf \
    && echo 'user=root' >> /etc/supervisord.conf \
    && echo 'logfile=/var/log/supervisord.log' >> /etc/supervisord.conf \
    && echo 'pidfile=/var/run/supervisord.pid' >> /etc/supervisord.conf \
    && echo '' >> /etc/supervisord.conf \
    && echo '[program:nginx]' >> /etc/supervisord.conf \
    && echo 'command=nginx -g "daemon off;"' >> /etc/supervisord.conf \
    && echo 'autostart=true' >> /etc/supervisord.conf \
    && echo 'autorestart=true' >> /etc/supervisord.conf \
    && echo 'stdout_logfile=/dev/stdout' >> /etc/supervisord.conf \
    && echo 'stdout_logfile_maxbytes=0' >> /etc/supervisord.conf \
    && echo 'stderr_logfile=/dev/stderr' >> /etc/supervisord.conf \
    && echo 'stderr_logfile_maxbytes=0' >> /etc/supervisord.conf \
    && echo '' >> /etc/supervisord.conf \
    && echo '[program:php-fpm]' >> /etc/supervisord.conf \
    && echo 'command=php-fpm' >> /etc/supervisord.conf \
    && echo 'autostart=true' >> /etc/supervisord.conf \
    && echo 'autorestart=true' >> /etc/supervisord.conf \
    && echo 'stdout_logfile=/dev/stdout' >> /etc/supervisord.conf \
    && echo 'stdout_logfile_maxbytes=0' >> /etc/supervisord.conf \
    && echo 'stderr_logfile=/dev/stderr' >> /etc/supervisord.conf \
    && echo 'stderr_logfile_maxbytes=0' >> /etc/supervisord.conf \
    && echo '' >> /etc/supervisord.conf \
    && echo '[program:redis]' >> /etc/supervisord.conf \
    && echo 'command=redis-server --protected-mode no' >> /etc/supervisord.conf \
    && echo 'autostart=true' >> /etc/supervisord.conf \
    && echo 'autorestart=true' >> /etc/supervisord.conf \
    && echo 'stdout_logfile=/dev/stdout' >> /etc/supervisord.conf \
    && echo 'stdout_logfile_maxbytes=0' >> /etc/supervisord.conf \
    && echo 'stderr_logfile=/dev/stderr' >> /etc/supervisord.conf \
    && echo 'stderr_logfile_maxbytes=0' >> /etc/supervisord.conf \
    && echo '' >> /etc/supervisord.conf \
    && echo '[program:pterodactyl-worker]' >> /etc/supervisord.conf \
    && echo 'command=php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3' >> /etc/supervisord.conf \
    && echo 'user=www-data' >> /etc/supervisord.conf \
    && echo 'autostart=true' >> /etc/supervisord.conf \
    && echo 'autorestart=true' >> /etc/supervisord.conf \
    && echo 'stdout_logfile=/dev/stdout' >> /etc/supervisord.conf \
    && echo 'stdout_logfile_maxbytes=0' >> /etc/supervisord.conf \
    && echo 'stderr_logfile=/dev/stderr' >> /etc/supervisord.conf \
    && echo 'stderr_logfile_maxbytes=0' >> /etc/supervisord.conf \
    && echo '' >> /etc/supervisord.conf \
    && echo '[program:cron]' >> /etc/supervisord.conf \
    && echo 'command=/usr/sbin/crond -f -L /dev/stdout' >> /etc/supervisord.conf \
    && echo 'autostart=true' >> /etc/supervisord.conf \
    && echo 'autorestart=true' >> /etc/supervisord.conf \
    && echo 'stdout_logfile=/dev/stdout' >> /etc/supervisord.conf \
    && echo 'stdout_logfile_maxbytes=0' >> /etc/supervisord.conf \
    && echo 'stderr_logfile=/dev/stderr' >> /etc/supervisord.conf \
    && echo 'stderr_logfile_maxbytes=0' >> /etc/supervisord.conf

# Set up cron job
RUN echo '* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1' > /etc/crontabs/www-data

# Clean up
RUN rm -rf /tmp/*

# Volumes for persistent data
VOLUME ["/var/www/pterodactyl/storage", "/var/www/pterodactyl/config", "/etc/nginx/certs"]

# Expose ports
EXPOSE 80 443

# Entry point
ENTRYPOINT ["/entrypoint.sh"]