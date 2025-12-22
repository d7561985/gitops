# syntax=docker/dockerfile:1
# PHP 8.2 with FPM for Symfony
FROM php:8.2-fpm-alpine

# Install php-extension-installer for fast extension installation
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

# Install system dependencies
RUN apk add --no-cache \
    nginx \
    supervisor \
    curl \
    git \
    zip \
    unzip \
    bash

# Install PHP extensions (uses pre-built binaries when available)
RUN install-php-extensions mongodb apcu pdo_mysql opcache

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Configure PHP
COPY docker/php/php.ini /usr/local/etc/php/conf.d/custom.ini

# Configure FPM
COPY docker/php/www.conf /usr/local/etc/php-fpm.d/www.conf

# Configure nginx
COPY docker/nginx/default.conf /etc/nginx/http.d/default.conf

# Configure supervisor
COPY docker/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Create app directory
WORKDIR /var/www

# Copy composer files first for better caching
COPY composer.json ./

# Set composer env to avoid memory issues
ENV COMPOSER_MEMORY_LIMIT=-1

# Install dependencies with GitLab authentication via .netrc
# .netrc is a standard mechanism that works with git, composer, npm, pip
# composer.json has "gitlab-protocol": "https" to force HTTPS for GitLab
# In CI: docker build --secret id=gitlab_token,env=CI_JOB_TOKEN ...
# Locally: docker build --secret id=gitlab_token,src=$HOME/.gitlab_token ...
RUN --mount=type=secret,id=gitlab_token \
    GITLAB_TOKEN=$(cat /run/secrets/gitlab_token 2>/dev/null | tr -d '\n' || echo "") && \
    if [ -n "$GITLAB_TOKEN" ]; then \
        echo "machine gitlab.com login gitlab-ci-token password ${GITLAB_TOKEN}" > ~/.netrc && \
        chmod 600 ~/.netrc; \
    fi && \
    composer install --no-scripts --no-autoloader --prefer-dist --no-dev --ignore-platform-req=ext-mongodb && \
    rm -f ~/.netrc

# Copy application files
COPY . .

# Generate autoloader
RUN composer dump-autoload --optimize

# Create necessary directories and set permissions
RUN mkdir -p var/cache var/log public/bundles /var/log/php var/cache/doctrine/odm/mongodb/Hydrators \
    && chown -R www-data:www-data var /var/log/php \
    && chmod -R 775 var /var/log/php

# Set environment to production
ENV APP_ENV=prod

# Install assets and clear cache (with dummy env vars for build time)
RUN MONGODB_URL="mongodb://localhost:27017" \
    MONGODB_DB="dummy" \
    SENTRY_DSN="" \
    SENTRY_ENVIRONMENT="dev" \
    SENTRY_TRACES_SAMPLE_RATE="1.0" \
    APP_VERSION="0.0.0" \
    php bin/console assets:install --env=prod --no-debug \
    && MONGODB_URL="mongodb://localhost:27017" \
    MONGODB_DB="dummy" \
    SENTRY_DSN="" \
    SENTRY_ENVIRONMENT="dev" \
    SENTRY_TRACES_SAMPLE_RATE="1.0" \
    APP_VERSION="0.0.0" \
    php bin/console cache:clear --env=prod --no-debug

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Expose port
EXPOSE 8085

# Start supervisor via entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
