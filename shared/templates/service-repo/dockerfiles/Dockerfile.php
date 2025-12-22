# =============================================================================
# PHP Service Dockerfile (FPM + Nginx)
# =============================================================================
# Final image: php:8.2-fpm-alpine with nginx (~150MB)
# Use for: Symfony, Laravel, general PHP services
#
# Note: Uses supervisor to run both FPM and Nginx
#
# Usage: Copy to your repo as 'Dockerfile'
# Requires: docker/php/, docker/nginx/, docker/supervisor/ directories
# =============================================================================

FROM php:8.2-fpm-alpine

# Install php-extension-installer for fast extension installation
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

# Install system dependencies
RUN apk add --no-cache \
    nginx \
    supervisor \
    curl

# Install PHP extensions (customize as needed)
# Common: pdo_mysql, pdo_pgsql, redis, mongodb, apcu, opcache
RUN install-php-extensions opcache apcu

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Configure PHP (create docker/php/php.ini)
COPY docker/php/php.ini /usr/local/etc/php/conf.d/custom.ini

# Configure FPM (create docker/php/www.conf)
COPY docker/php/www.conf /usr/local/etc/php-fpm.d/www.conf

# Configure nginx (create docker/nginx/default.conf)
COPY docker/nginx/default.conf /etc/nginx/http.d/default.conf

# Configure supervisor (create docker/supervisor/supervisord.conf)
COPY docker/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

WORKDIR /var/www

# Copy composer files first for better caching
COPY composer.json composer.lock* ./

# Install dependencies
ENV COMPOSER_MEMORY_LIMIT=-1
RUN composer install --no-scripts --no-autoloader --prefer-dist --no-dev

# Copy application files
COPY . .

# Generate autoloader
RUN composer dump-autoload --optimize

# Create directories and set permissions
RUN mkdir -p var/cache var/log \
    && chown -R www-data:www-data var \
    && chmod -R 775 var

ENV APP_ENV=prod

EXPOSE 8080

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
