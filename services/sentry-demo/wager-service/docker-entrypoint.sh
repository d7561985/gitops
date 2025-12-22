#!/bin/sh
set -e

# Clear Symfony cache first
rm -rf /var/www/var/cache/*
rm -rf /var/www/var/log/*

# Create required directories
mkdir -p /var/www/var/cache/doctrine/odm/mongodb/Hydrators
mkdir -p /var/www/var/cache/prod
mkdir -p /var/www/var/log
mkdir -p /var/log/php

# Set ownership for all var directories
chown -R www-data:www-data /var/www/var
chown -R www-data:www-data /var/log/php

# Set permissions
chmod -R 775 /var/www/var
chmod -R 775 /var/log/php

# Warm up Symfony cache as www-data
su -s /bin/sh www-data -c "cd /var/www && php bin/console cache:warmup --env=prod"

# Start supervisor
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf