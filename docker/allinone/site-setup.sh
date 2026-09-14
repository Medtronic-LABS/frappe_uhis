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
: "${DB_ROOT_PASSWORD:?DB_ROOT_PASSWORD must be set}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD must be set}"

cd /home/frappe/frappe-bench
MARKER="sites/.site_setup_complete"
rm -f "${MARKER}"

echo "[site-setup] waiting for MariaDB and Redis to accept connections"
for i in $(seq 1 60); do
	mysqladmin -h 127.0.0.1 -uroot -p"${DB_ROOT_PASSWORD}" ping >/dev/null 2>&1 && break
	sleep 2
done
mysqladmin -h 127.0.0.1 -uroot -p"${DB_ROOT_PASSWORD}" ping >/dev/null 2>&1 || {
	echo "[site-setup] MariaDB never became reachable — aborting" >&2
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
	echo "[site-setup] creating site '${SITE_NAME}'"
	# mariadb-uhis.cnf binds to 127.0.0.1 with skip-name-resolve off, so MariaDB
	# resolves any loopback TCP connection's apparent host as literally 'localhost'
	# (confirmed empirically: a user granted only '%' is rejected over this same TCP
	# connection that a 'localhost'-scoped user authenticates fine over) — scope the
	# new site's DB user to 'localhost' to match, not the more common '%' wildcard.
	bench new-site "${SITE_NAME}" \
		--db-host 127.0.0.1 \
		--db-root-password "${DB_ROOT_PASSWORD}" \
		--admin-password "${ADMIN_PASSWORD}" \
		--mariadb-user-host-login-scope=localhost
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
