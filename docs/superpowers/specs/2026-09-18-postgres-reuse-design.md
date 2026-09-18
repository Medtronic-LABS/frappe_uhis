# Reuse an existing Postgres connection + schema (drop in-container MariaDB)

## Why

The all-in-one image (`docker/allinone/`) currently bundles its own MariaDB server,
started and initialized inside the same container by `entrypoint.sh`/`supervisord`.
The target deployment already has a Postgres database + schema, shared with an
existing Python service that already owns some tables in that schema. We want uhis
to add its own (Frappe `tab`-prefixed) tables into that same schema over the network,
without running any additional database container and without touching the other
service's existing tables.

## Decision: which "reuse" this is

Two shapes were considered:

1. Point at an existing Postgres *server*, but let Frappe provision its own fresh
   database on it (Frappe's native `--db-type postgres` flow, unmodified).
2. Point at an existing, already-populated *database + schema* that Frappe must not
   create or drop, and must coexist inside.

This is shape 2, confirmed by the existing schema already having another service's
tables in it.

## How Frappe supports this

Confirmed directly in the `frappe` framework source (not assumed):

- `bench new-site` accepts `--db-type postgres`.
- `frappe.database.postgres.database.PostgresDatabase.db_schema` reads
  `frappe.conf.get("db_schema", "public")` and issues `SET search_path TO <schema>`
  on every connection — this is the mechanism that scopes Frappe's tables to a
  specific schema instead of `public`.
- **There is no `--db-schema` CLI flag** on `bench new-site`. `db_schema` can only
  come from config that already exists *before* the site-creation process makes its
  first connection — i.e. `common_site_config.json`, not the site's own
  `site_config.json` (which doesn't exist yet when the process starts).
- `bench new-site --no-setup-db` skips `setup_database()` entirely — normally that
  function runs `DROP DATABASE IF EXISTS` / `CREATE DATABASE` / `CREATE USER`, which
  would be destructive against a shared, already-populated database. With
  `--no-setup-db`, `install_db()` goes straight to `bootstrap_database()`, which
  connects with the supplied (already-existing, already-permissioned) `--db-user` /
  `--db-password` and creates only Frappe's own tables.
- `psycopg2-binary` is already a declared `frappe` dependency (`pyproject.toml`) —
  no extra Python packaging needed.

## Known risk, accepted

`frappe_theme`'s version-history / change-log feature (`version_utils.py`, `api.py`)
runs raw SQL using MariaDB-only `JSON_TABLE()` (8 call sites). This has no Postgres
equivalent in that form and will error on Postgres. **Decision: ship anyway, fix
separately.** Not in scope for this change.

## What changes

**Removed entirely:** `mariadb-server`, `mariadb-client` from the image;
`mariadb-uhis.cnf`; the `[program:mariadbd]` supervisord entry; `entrypoint.sh`'s
first-boot `mariadb-install-db` + root-password logic; the `/var/lib/mysql` volume.
Redis is unaffected — still bundled in-container, unchanged.

**`common_site_config.json` is now written by `entrypoint.sh` at every container
boot, not baked at build time.** `db_host`/`db_port`/`db_schema` are deployment
values that don't exist at image-build time (unlike the old hardcoded
`127.0.0.1:3306`, which was always true for an in-container MariaDB). The
build-time file (still created in the Dockerfile, still stashed into
`sites-seed/` for `apps.txt`/`apps.json`/`assets`) keeps only the Redis config;
`entrypoint.sh` overwrites `sites/common_site_config.json` fresh on every boot from
`DB_HOST`, `DB_PORT` (default `5432`), and `DB_SCHEMA` env vars, plus the same
hardcoded `db_type: postgres` and Redis values.

**`site-setup.sh`** requires `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`,
`DB_SCHEMA` (replacing `DB_ROOT_PASSWORD`, which no longer exists anywhere — no
root/superuser credential is needed at any point, since nothing creates or drops a
database or role). The MariaDB/Redis readiness poll (`mysqladmin ping`) becomes a
Postgres readiness poll (`pg_isready`). The `bench new-site` call becomes:

```bash
bench new-site "${SITE_NAME}" \
  --no-setup-db \
  --db-type postgres \
  --db-host "${DB_HOST}" \
  --db-port "${DB_PORT}" \
  --db-name "${DB_NAME}" \
  --db-user "${DB_USER}" \
  --db-password "${DB_PASSWORD}" \
  --admin-password "${ADMIN_PASSWORD}"
```

The per-app `bench install-app` loop is unchanged — it doesn't depend on the DB
engine.

**Dockerfile:** swaps `mariadb-server`/`mariadb-client` for `postgresql-client`
(provides `pg_isready`, useful for manual debugging too); drops all
`/var/lib/mysql`/`/run/mysqld` init and the `mariadb-uhis.cnf` COPY.

## Explicit preconditions (outside this repo's control)

1. The `DB_USER` role already has `CREATE`/`USAGE` privileges on `DB_SCHEMA` — this
   change cannot grant that.
2. The container has network reachability to `DB_HOST:DB_PORT` (VPC/security group
   or Docker network) — an infra precondition, not something these scripts fix.

## Secrets/config, for clarity

`DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/`DB_PASSWORD`/`DB_SCHEMA` are **container
runtime env vars**, supplied via the deploy host's `.env`/`docker-compose.yml` — the
same mechanism `SITE_NAME`/`ADMIN_PASSWORD` already use. They are not GitHub Actions
secrets; the CI workflow never sees them.

## Scope

Applied identically to both `uhis/docker/allinone/` (what's actually deployed) and
`spice_next_core/docker/allinone/` (used for that repo's own local sanity-check
builds) — the two are already deliberately kept as mirrors of each other.

## Testing

Local `docker build` + `docker run` against a throwaway local Postgres with a
pre-existing schema and one dummy table (simulating the other service's data),
confirming: `bench new-site --no-setup-db` succeeds and does not touch the dummy
table; `bench --site <site> list-apps` shows all 5 apps; `pg_isready`-based readiness
polling and the container's health path behave the same as the MariaDB version did.
