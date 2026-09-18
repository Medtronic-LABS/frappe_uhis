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
the compose file the deploy job runs on the production host; copy `.env.example`
to `.env` there and fill in the real `SITE_NAME`/`ADMIN_PASSWORD`/`DB_*` values
(Postgres is an existing, external database/schema — see
`docs/superpowers/specs/2026-09-18-postgres-reuse-design.md`). The deploy job
does not clone this repo onto the host; keep the host's copy of
`docker-compose.yml` in sync with this one by hand.

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
