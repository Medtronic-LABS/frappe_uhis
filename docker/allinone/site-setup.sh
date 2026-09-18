#!/bin/bash
# One-shot supervisord program: create the site (if missing), install every app
# uhis depends on (if missing) in required_apps dependency order, always run
# bench migrate and clear-cache, then drop a marker file that wait-for-site.sh
# polls for. Mirrors spice_next_core's docker/allinone/site-setup.sh, extended
# for uhis's own dependency chain (see uhis/hooks.py required_apps) — safe to
# automate here because this image is deliberately single-instance (no concurrent
# replicas to race on schema migration or cache invalidation).
set -eu

: "${SITE_NAME:?SITE_NAME must be set}"
: "${DB_HOST:?DB_HOST must be set}"
: "${DB_NAME:?DB_NAME must be set}"
: "${DB_USER:?DB_USER must be set}"
: "${DB_PASSWORD:?DB_PASSWORD must be set}"
: "${DB_SCHEMA:?DB_SCHEMA must be set}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD must be set}"
DB_PORT="${DB_PORT:-5432}"

# bench new-site's own bootstrap-SQL import (DbManager.restore_database) shells
# out directly to `psql 'postgresql://user:pass@host:port/db'` with no schema in
# the connection string at all -- it never runs the `SET search_path` that
# Frappe's own ORM connection does for every other query. Without this, that
# import silently creates all of Frappe's base tables in `public` instead of
# DB_SCHEMA, and bench then reports "Table 'tabDefaultValue' missing" because it
# correctly looked for it in DB_SCHEMA. PGOPTIONS is honored by libpq/psql as
# the default search_path for any new connection made under this environment,
# including that raw subprocess -- confirmed nothing in frappe's own code sets
# this, so there's no conflict with its explicit SET search_path calls.
export PGOPTIONS="-c search_path=${DB_SCHEMA}"

cd /home/frappe/frappe-bench
MARKER="sites/.site_setup_complete"
rm -f "${MARKER}"

echo "[site-setup] waiting for Postgres and Redis to accept connections"
for i in $(seq 1 60); do
	pg_isready -h "${DB_HOST}" -p "${DB_PORT}" >/dev/null 2>&1 && break
	sleep 2
done
pg_isready -h "${DB_HOST}" -p "${DB_PORT}" >/dev/null 2>&1 || {
	echo "[site-setup] Postgres never became reachable — aborting" >&2
	exit 1
}
for i in $(seq 1 60); do
	redis-cli -h 127.0.0.1 -p 6379 ping >/dev/null 2>&1 && break
	sleep 2
done
redis-cli -h 127.0.0.1 -p 6379 ping >/dev/null 2>&1 || {
	echo "[site-setup] Redis never became reachable — aborting" >&2
	exit 1
}

if [ -d "sites/${SITE_NAME}" ]; then
	echo "[site-setup] site '${SITE_NAME}' already exists — skipping bench new-site"
else
	echo "[site-setup] creating site '${SITE_NAME}' against existing schema '${DB_SCHEMA}'"
	# --no-setup-db: DB_NAME/DB_SCHEMA already exist and are shared with another
	# service's tables, so this must NOT run Frappe's normal DROP DATABASE/CREATE
	# DATABASE/CREATE USER step -- --no-setup-db skips straight to creating only
	# Frappe's own (tab-prefixed) tables, using the already-granted DB_USER role.
	# db_schema itself comes from common_site_config.json (written by
	# entrypoint.sh from DB_SCHEMA) -- there's no --db-schema flag here; Frappe
	# reads it before this process's first connection. See
	# docs/superpowers/specs/2026-09-18-postgres-reuse-design.md.
	bench new-site "${SITE_NAME}" \
		--no-setup-db \
		--db-type postgres \
		--db-host "${DB_HOST}" \
		--db-port "${DB_PORT}" \
		--db-name "${DB_NAME}" \
		--db-user "${DB_USER}" \
		--db-password "${DB_PASSWORD}" \
		--admin-password "${ADMIN_PASSWORD}"
fi

# Installed in required_apps dependency order: frappe_theme -> spice_next_core ->
# shukhee_integration / leapwell_telemetry -> uhis. Each app's own required_apps
# chain would install its dependencies automatically on a genuinely fresh site,
# but this explicit, idempotent per-app check also covers a site that had an
# earlier app installed BEFORE a dependency was declared, where required_apps
# recursion never retroactively runs.
for app in frappe_theme spice_next_core shukhee_integration leapwell_telemetry uhis; do
	if bench --site "${SITE_NAME}" list-apps | grep -qx "${app}"; then
		echo "[site-setup] ${app} already installed on '${SITE_NAME}'"
	else
		echo "[site-setup] installing ${app} on '${SITE_NAME}'"
		bench --site "${SITE_NAME}" install-app "${app}"
	fi
done

echo "[site-setup] running bench migrate"
bench --site "${SITE_NAME}" migrate

echo "[site-setup] clearing cache"
bench --site "${SITE_NAME}" clear-cache

echo "[site-setup] done"
touch "${MARKER}"
