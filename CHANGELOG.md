# Changelog

`uhis` is the client-specific deployment app (`required_apps = spice_next_core,
shukhee_integration, leapwell_telemetry` — see `uhis/hooks.py`) whose
`docker-publish.yml` CI/CD builds and deploys the all-in-one production image
bundling all of those apps. This file tracks notable changes in those
dependency ("parent") apps that land in this deployment, alongside `uhis`'s
own changes, since a change in a dependency app only actually reaches
production once something here triggers a rebuild.

## Unreleased — Teleconsult consent: embedded in Call Logs at booking

### `shukhee_integration` (dependency app, checked out at its `main` ref by `docker-publish.yml`)

Replaces the two-record consent design (a separate `Shukhee Consent Log`
doctype plus an after-the-fact linking step, matched on `encounter_id`/
`visit_id`) with a single-request design:

- `start_consultation` now resolves and embeds the consent decision directly
  onto the `Call Logs` row it inserts (new `consent_version`/`consent_lng`/
  `consent_items`/`consent_filled_text` fields, plus a new `Call Log Consent
  Item` child doctype) — the Agreed decision rides along in the same request
  that books the call, instead of being recorded separately and linked
  afterward.
- New `record_consent_decline` endpoint for the Decline path (new, lightweight
  `Shukhee Consent Decline` doctype) — a Decline never produces a Call Logs
  row, so this is its only record.
- Retires the old `Shukhee Consent Log`/`Shukhee Consent Log Item` doctypes
  and the `attach_consent_to_call`/`get_call_consent` endpoints via a
  `post_model_sync` patch.

This removes an entire class of bugs the old two-record design produced: a
deferred local upload racing the synchronous booking call, wedged sync state
silently blocking the upload forever, a version-only match that could
cross-attach a different patient's decision, and a plumbing bug that sent an
empty `patientId`.

### `uhis` (this app)

No functional changes of its own in this release — this entry exists to
trigger `docker-publish.yml` so the image is rebuilt against
`shukhee_integration`'s current `main` (which now includes the consent
changes above) and redeployed.
