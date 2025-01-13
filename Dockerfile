FROM debian:bullseye

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget gnupg2 gosu tini\
    && rm -rf /var/lib/apt/lists/* \
    # verify that the binary works
    && gosu nobody true

RUN apt-get update && apt-get install -y postgresql-common \
    && /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y 
# Install postgres clients so that barman can use the appropriate version when
# using pg_basebackup.
# Install some other requirements as well.
#   cron: For scheduling base backups
#   gcc: For building psycopg2
#   libpq-dev: Needed to build/run psycopg2
#   libpython-dev: For building psycopg2
#   openssh-client: Needed to rsync basebackups from the database servers
#   python: Needed to run barman
#   rsync: Needed to rsync basebackups from the database servers
#   gettext-base: envsubst
RUN apt-get update && apt-get install -y --no-install-recommends \
    cron \
    gcc \
    libpq-dev \
    libpython3-dev \
    openssh-client \
    postgresql-17 \
    python3 \
    python3-distutils \
    rsync \
    gettext-base \
    procps \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/crontab /etc/cron.*/* \
    && sed -i 's/\(.*pam_loginuid.so\)/#\1/' /etc/pam.d/cron \
    && mkdir -p /etc/barman/barman.d

# add postgresql-17 binaries to PATH
ENV PATH /usr/lib/postgresql/17/bin:$PATH

# pg_combinebackup is installed
RUN pg_basebackup --version && pg_combinebackup --version

# Set up some defaults for file/directory locations used in entrypoint.sh.
ENV \
    BARMAN_VERSION=3.12.1 \
    BARMAN_CRON_SRC=/private/cron.d \
    BARMAN_DATA_DIR=/var/lib/barman \
    BARMAN_LOG_DIR=/var/log/barman \
    BARMAN_SSH_KEY_DIR=/private/ssh \
    BARMAN_CRON_SCHEDULE="* * * * *" \
    BARMAN_BACKUP_SCHEDULE="0 4 * * *" \
    BARMAN_LOG_LEVEL=INFO \
    POSTGRES_SERVER=pg \
    POSTGRES_PORT=5432 \
    BARMAN_SUPERUSER=postgres \
    BARMAN_SUPERUSER_PASSWORD=postgres \
    POSTGRES_DB=postgres \
    BARMAN_REPLICATION_USER=standby \
    BARMAN_REPLICATION_PASSWORD=standby \
    BARMAN_DB_SLOT_NAME=barman \
    BARMAN_DB_BACKUP_METHOD=postgres \
    BARMAN_EXPORTER_SCHEDULE="*/5 * * * *" \
    BARMAN_EXPORTER_LISTEN_ADDRESS="0.0.0.0" \
    BARMAN_EXPORTER_LISTEN_PORT=9780 \
    BARMAN_EXPORTER_CACHE_TIME=3600
VOLUME ${BARMAN_DATA_DIR}

COPY install_barman.sh /tmp/
RUN /tmp/install_barman.sh && rm /tmp/install_barman.sh
COPY barman.conf.template /etc/barman.conf.template
COPY pg.conf.template /etc/barman/barman.d/pg.conf.template

# Install barman exporter
RUN pip install barman-exporter && mkdir /node_exporter
VOLUME /node_exporter

# Install the entrypoint script.  It will set up ssh-related things and then run
# the CMD which, by default, starts cron.  The 'barman -q cron' job will get
# pg_receivexlog running.  Cron may also have jobs installed to run
# 'barman backup' periodically.
ENTRYPOINT ["tini", "--", "/entrypoint.sh"]
CMD ["cron", "-L", "4",  "-f"]
COPY entrypoint.sh /
WORKDIR ${BARMAN_DATA_DIR}
