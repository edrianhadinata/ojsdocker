FROM php:8.4-apache

LABEL maintainer="OJS Docker - PHP 8.4 + Apache2"
LABEL description="Open Journal Systems dengan PHP 8.4 dan Apache2"

# ─── Environment Variables ────────────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive
ENV OJS_VERSION=3.4.0-10
ENV OJS_CLI_INSTALL=0
ENV SERVERNAME=localhost

# ─── Install System Dependencies ─────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libwebp-dev \
    libzip-dev \
    libicu-dev \
    libxml2-dev \
    libxslt1-dev \
    libcurl4-openssl-dev \
    libonig-dev \
    libssl-dev \
    unzip \
    zip \
    git \
    curl \
    cron \
    supervisor \
    nano \
    && rm -rf /var/lib/apt/lists/*

# ─── Install PHP Extensions ───────────────────────────────────────────────────
RUN docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
    && docker-php-ext-install -j$(nproc) \
        gd \
        mbstring \
        mysqli \
        pdo \
        pdo_mysql \
        intl \
        xml \
        xsl \
        zip \
        curl \
        bcmath \
        opcache \
        exif \
        fileinfo

# ─── Install Composer ────────────────────────────────────────────────────────
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# ─── Apache Configuration ────────────────────────────────────────────────────
RUN a2enmod rewrite \
    && a2enmod ssl \
    && a2enmod headers \
    && a2enmod expires \
    && a2enmod deflate

# ─── PHP Configuration ───────────────────────────────────────────────────────
COPY config/php.ini /usr/local/etc/php/conf.d/ojs-custom.ini

# ─── Apache VirtualHost ──────────────────────────────────────────────────────
COPY config/ojs.conf /etc/apache2/sites-available/000-default.conf

# ─── Download & Extract OJS ──────────────────────────────────────────────────
RUN curl -sL "https://pkp.sfu.ca/ojs/download/ojs-${OJS_VERSION}.tar.gz" \
        -o /tmp/ojs.tar.gz \
    && tar -xzf /tmp/ojs.tar.gz -C /tmp \
    && cp -a /tmp/ojs-*/. /var/www/html/ \
    && rm -rf /tmp/ojs* \
    && find /var/www/html -type d -exec chmod 755 {} \; \
    && find /var/www/html -type f -exec chmod 644 {} \;

# ─── Buat direktori upload OJS (di luar webroot) ─────────────────────────────
RUN mkdir -p /var/ojs-files \
    && chown -R www-data:www-data /var/ojs-files \
    && chmod -R 755 /var/ojs-files

# ─── Set permission direktori OJS ────────────────────────────────────────────
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html/cache \
    && chmod -R 755 /var/www/html/public

# ─── Supervisord Config ───────────────────────────────────────────────────────
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ─── Entrypoint Script ────────────────────────────────────────────────────────
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/var/www/html/public", "/var/ojs-files"]

EXPOSE 80 443

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
