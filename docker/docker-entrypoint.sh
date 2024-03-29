#!/bin/bash
set -e

a2enmod rewrite

if [ "$USER" = "root" ]; then

    # set localtime
    ln -sf /usr/share/zoneinfo/$LOCALTIME /etc/localtime

    # secure path
    chmod a-rwx -R /etc/apache2/ $PHP_INI_DIR/ /etc/ssmtp
fi

#
# functions

function set_conf {
    echo ''>$2; IFSO=$IFS; IFS=$(echo -en "\n\b")
    for c in `printenv|grep $1`; do echo "`echo $c|cut -d "=" -f1|awk -F"$1" '{print $2}'` $3 `echo $c|cut -d "=" -f2`" >> $2; done;
    IFS=$IFSO
}

#
# APACHE

if [ ! -d "$HTTPD__DocumentRoot" ]; then echo >&2 "[Error] Document Root Directory not exist (please create $HTTPD__DocumentRoot)"; exit 1; fi
if [ "$HTTPD_a2enmod" != "" ]; then a2enmod $HTTPD_a2enmod > /dev/null; fi;
set_conf "HTTPD__" "$HTTPD_CONF_DIR/40-user.conf" ""

#
# PHP

echo "date.timezone = \"${LOCALTIME}\"" >> $PHP_INI_DIR/conf.d/00-default.ini
if [ "$PHP_php5enmod" != "" ]; then docker-php-ext-enable $PHP_php5enmod > /dev/null 2>&1; fi;
set_conf "PHP__" "$PHP_INI_DIR/conf.d/40-user.ini" "="

#
# docker links

# Deprecated - Set memcached server with link
if [ -n "$PHP_MEMCACHED_PORT_11211_TCP_ADDR" ]; then
    echo "[WARNING] Deprecated - Future versions of Docker will not support links - you should remove them for forwards-compatibility."
    echo "session.save_handler = memcached" > $PHP_INI_DIR/conf.d/20-memcached.ini
    echo "session.save_path = $PHP_MEMCACHED_PORT_11211_TCP_ADDR:$PHP_MEMCACHED_PORT_11211_TCP_PORT" >> $PHP_INI_DIR/conf.d/20-memcached.ini
elif [ -f $PHP_INI_DIR/conf.d/20-memcached.ini ]; then
    rm $PHP_INI_DIR/conf.d/20-memcached.ini
fi

# Deprecated - Set ssmtp server with link
if [ -n "$SMTP_PORT_25_TCP_ADDR" ]; then
    echo "[WARNING] Deprecated - Future versions of Docker will not support links - you should remove them for forwards-compatibility."
    echo 'sendmail_path = /usr/sbin/ssmtp -t' >> $PHP_INI_DIR/conf.d/00-default.ini
    sed -i "s/mailhub=.*/mailhub=$SMTP_PORT_25_TCP_ADDR:$SMTP_PORT_25_TCP_PORT/"  /etc/ssmtp/ssmtp.conf
fi

# Set memcached session save handle
if [ -n "$MEMCACHED" ]; then
    if [ ! -f $PHP_INI_DIR/conf.d/docker-php-ext-memcached.ini ]; then docker-php-ext-enable  memcached > /dev/null; fi

    IFSO=$IFS; IFS=' ' read -ra BACKENDS <<< "${MEMCACHED}"
    for BACKEND in "${BACKENDS[@]}"; do
        SAVE_PATH="${SAVE_PATH}${BACKEND}?${MEMCACHED_CONFIG:-persistent=1&timeout=5&retry_interval=30},"
    done; IFS=$IFSO;

cat << EOF >> $PHP_INI_DIR/conf.d/20-memcached.ini
    session.save_handler = memcached
    session.save_path = "${SAVE_PATH}"
EOF

fi

# Set ssmtp server
if [ -n "$SMTP" ]; then
    echo 'sendmail_path = /usr/sbin/ssmtp -t' >> $PHP_INI_DIR/conf.d/00-default.ini
    sed -i "s/mailhub=.*/mailhub=${SMTP}/"  /etc/ssmtp/ssmtp.conf
fi

#
# Run

# Install composer

if [[ -f /var/www/composer.json ]]; then
    cd /var/www
    composer install --prefer-dist --no-progress --no-suggest --no-interaction --no-plugins --no-dev
    composer dump-autoload -o
    #bin/console doctrine:database:create  --no-interaction
    #bin/console doctrine:migration:migrate  --allow-no-migration --no-interaction
fi


if [[ -f /etc/apache2/sites-enabled/000-default.conf ]]; then
    rm /etc/apache2/sites-enabled/000-default.conf
fi

chmod 777 -Rf /var/www

if [[ ! -z "$1" ]]; then
    exec ${*}
else
    exec apache2-foreground
fi
