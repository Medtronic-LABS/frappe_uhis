# All-in-one production image: bench (Frappe + frappe_theme + spice_next_core +
# shukhee_integration + leapwell_telemetry + uhis) + MariaDB + Redis, all running
# as supervised processes in one container. Built and pushed to GHCR by
# .github/workflows/docker-publish.yml on every merge to main / version tag.
#
# uhis is the client-specific app (required_apps = spice_next_core,
# shukhee_integration, leapwell_telemetry — see uhis/hooks.py) that assembles
# everything this deployment actually ships, which is why the production image
# and its CI/CD pipeline live here rather than in spice_next_core (a shared core
# package reused across deployments). Modeled directly on spice_next_core's own
# docker/allinone/ image — see frappe-uhis-next/docs/deployment/production.md for
# the full architecture.
FROM frappe/bench:latest

# Defaults to root for the rest of the build (apt-get, chown) regardless of the base
# image's own final USER — supervisord itself runs as root at container start so it
# can drop privileges per-program (mariadb as `mysql`, everything else as `frappe`).
USER root

ARG FRAPPE_BRANCH=version-15
ENV PATH="/home/frappe/.local/bin:${PATH}"

RUN apt-get update \
	&& DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		mariadb-server \
		mariadb-client \
		redis-server \
		supervisor \
		gosu \
		curl \
	&& rm -rf /var/lib/apt/lists/* \
	&& mkdir -p /var/log/supervisor /var/lib/mysql /run/mysqld \
	&& chown -R mysql:mysql /var/lib/mysql /run/mysqld \
	&& chown -R frappe:frappe /var/log/supervisor \
	# The mariadb-server postinst auto-initializes a datadir here at package-install
	# time (with its own default, unusable root credentials). /var/lib/mysql is a
	# declared VOLUME — Docker seeds a fresh named volume from whatever the image has
	# baked in at that path, so leaving this populated would silently skip our own
	# entrypoint.sh first-boot init (mariadb-install-db + password set) on every
	# genuinely-fresh deployment. Must stay empty in the image.
	&& rm -rf /var/lib/mysql/*

COPY apps/uhis/docker/allinone/mariadb-uhis.cnf /etc/mysql/mariadb.conf.d/60-uhis-next.cnf

USER frappe
WORKDIR /home/frappe

# Defensive — frappe/bench:latest does not guarantee bench-cli is preinstalled
# (same check frappe_setup.sh does for the dev bench).
RUN command -v bench >/dev/null 2>&1 || pip3 install --user --break-system-packages frappe-bench

RUN bench init --frappe-branch "${FRAPPE_BRANCH}" --python python3 \
	--skip-redis-config-generation --no-backups frappe-bench

WORKDIR /home/frappe/frappe-bench

# frappe_theme is a public dependency of spice_next_core (its hooks.py declares
# required_apps = ["frappe_theme"]) — fetched directly, no CI checkout needed.
# Guarded on apps/frappe_theme so a rebuild that already has it on disk (e.g. a
# cached layer restored from a build-context mount) doesn't re-clone it.
RUN [ -d apps/frappe_theme ] || bench get-app --branch development https://github.com/Suvaidyam/frappe_theme

# spice_next_core, shukhee_integration, leapwell_telemetry, and uhis itself are all
# CI checkouts of THIS workflow run (see .github/workflows/docker-publish.yml), not
# re-clones from GitHub — the exact commits under test are already on disk, so this
# avoids a build-time GitHub credential and any ref-drift between "what CI tested"
# and "what got baked into the image". Copied in required_apps dependency order:
# spice_next_core (needs frappe_theme) -> shukhee_integration / leapwell_telemetry
# (need spice_next_core) -> uhis (needs all three).
COPY --chown=frappe:frappe apps/spice_next_core     apps/spice_next_core
COPY --chown=frappe:frappe apps/shukhee_integration apps/shukhee_integration
COPY --chown=frappe:frappe apps/leapwell_telemetry  apps/leapwell_telemetry
COPY --chown=frappe:frappe apps/uhis                apps/uhis

# frappe.get_all_apps() (what `bench install-app` and `bench build` both use to decide
# which apps exist in this bench) reads sites/apps.txt — NOT the bench-root apps.txt.
# sites/apps.txt is rewritten wholesale (not appended) because `bench init` leaves it
# without a trailing newline — a naive `echo ... >> sites/apps.txt` silently
# concatenates onto the previous line, which frappe then can't resolve as an
# installed app at all (see spice_next_core's Dockerfile for the exact failure this
# avoids). Order matches required_apps dependency order above.
RUN ./env/bin/pip install --no-cache-dir \
		-e ./apps/spice_next_core \
		-e ./apps/shukhee_integration \
		-e ./apps/leapwell_telemetry \
		-e ./apps/uhis \
	&& printf 'frappe\nfrappe_theme\nspice_next_core\nshukhee_integration\nleapwell_telemetry\nuhis\n' > sites/apps.txt

# Bench-level config: single in-container MariaDB + single in-container Redis
# instance serving all three of Frappe's logical roles via DB index.
RUN cat > sites/common_site_config.json <<'JSON'
{
  "db_host": "127.0.0.1",
  "db_port": 3306,
  "redis_cache": "redis://127.0.0.1:6379/0",
  "redis_queue": "redis://127.0.0.1:6379/1",
  "redis_socketio": "redis://127.0.0.1:6379/2",
  "socketio_port": 9000
}
JSON

# Build JS/CSS assets now so the running container never runs `bench build`
# (yarn-install-heavy, network-dependent) at start time.
RUN bench build

# Mounting a volume anywhere under sites/ at runtime shadows whatever was baked
# there at build time. Stash a copy of the generated (never hand-edited) files
# outside sites/ so entrypoint.sh can re-materialize them into the (possibly empty)
# mounted sites/ on every boot.
RUN mkdir -p /home/frappe/sites-seed \
	&& cp sites/common_site_config.json /home/frappe/sites-seed/common_site_config.json \
	&& cp sites/apps.txt               /home/frappe/sites-seed/apps.txt \
	&& cp sites/apps.json              /home/frappe/sites-seed/apps.json \
	&& cp -r sites/assets              /home/frappe/sites-seed/assets

USER root
COPY apps/uhis/docker/allinone/supervisord.conf   /etc/supervisor/supervisord.conf
COPY apps/uhis/docker/allinone/entrypoint.sh      /usr/local/bin/entrypoint.sh
COPY apps/uhis/docker/allinone/site-setup.sh      /usr/local/bin/site-setup.sh
COPY apps/uhis/docker/allinone/wait-for-site.sh   /usr/local/bin/wait-for-site.sh
COPY apps/uhis/docker/allinone/run-backend.sh     /usr/local/bin/run-backend.sh
# NOT /etc/redis/ — that directory ships as drwxrws--- owned by redis:redis (from the
# apt redis-server package), unreadable by the `frappe` user this process runs as.
COPY apps/uhis/docker/allinone/redis-uhis.conf    /home/frappe/redis-uhis.conf
# Bench root, NOT sites/ — sites/ is the mounted VOLUME, so anything placed there at
# build time gets shadowed at runtime (same reason common_site_config.json etc. need
# the sites-seed re-materialization dance). run-backend.sh adds this directory to
# gunicorn's --pythonpath so `wsgi:application` still resolves with --chdir into
# sites/ (required for frappe's own site resolution).
COPY apps/uhis/docker/allinone/wsgi.py            /home/frappe/frappe-bench/wsgi.py
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/site-setup.sh \
		/usr/local/bin/wait-for-site.sh /usr/local/bin/run-backend.sh \
	&& mkdir -p /home/frappe/.redis \
	&& chown -R frappe:frappe /home/frappe/frappe-bench /home/frappe/sites-seed \
		/home/frappe/.redis /home/frappe/redis-uhis.conf

EXPOSE 8000 9000

VOLUME ["/var/lib/mysql", "/home/frappe/frappe-bench/sites"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
