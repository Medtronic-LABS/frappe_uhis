### Uhis

Client-facing umbrella app for UHIS-Next -- depends on spice_next_core, shukhee_integration, and leapwell_telemetry.

### Installation

You can install this app using the [bench](https://github.com/frappe/bench) CLI:

```bash
cd $PATH_TO_YOUR_BENCH
bench get-app $URL_OF_THIS_REPO --branch version-16
bench install-app uhis
```

### Deployment

uhis is the sole owner of the production image, CI/CD pipeline, and deployment
target for this stack — see `.github/workflows/docker-publish.yml` and
`docker/allinone/` for the build. `docker-compose.yml` (root of this repo) is
the compose file the deploy job runs on the production host.

The `deploy` job (push to `main` only) is fully self-provisioning: it SSHes into
the host, clones this repo on first run (fast-forwards to `origin/main` on every
run after), writes `.env` fresh from GitHub repo secrets, then runs
`docker compose up -d frappe-uhis`. Required repo secrets, beyond the 4 SSH ones
(`DEPLOY_HOST`/`DEPLOY_USER`/`DEPLOY_SSH_KEY`/`DEPLOY_PORT`): `SITE_NAME`,
`ADMIN_PASSWORD`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`,
`DB_SCHEMA` (Postgres is an existing, external database/schema — see
`docs/superpowers/specs/2026-09-18-postgres-reuse-design.md`). `.env` on the
host is CI-owned and rewritten on every deploy, not hand-edited — `.env.example`
is only for a manual/local `docker compose up -d`.

### Contributing

This app uses `pre-commit` for code formatting and linting. Please [install pre-commit](https://pre-commit.com/#installation) and enable it for this repository:

```bash
cd apps/uhis
pre-commit install
```

Pre-commit is configured to use the following tools for checking and formatting your code:

- ruff
- eslint
- prettier
- pyupgrade

### License

gpl-3.0
