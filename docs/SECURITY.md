# Security, privacy and encryption

**Authentication is intentionally not implemented in this prototype.** Reviews are attributed to a
configurable local identity (`EAGLEEYE_REVIEWER_IDENTITY`, default `local-demo-reviewer`), shown as such
in the UI, the audit trail and reports. Do not expose this build on an untrusted network.

Implemented now:
* Upload validation: allowed kinds only, extension **and** file signature must match, size limits, PIL
  decompression-bomb limit, PDF encryption/page checks, spreadsheet parsing errors surfaced as 400.
* Storage keys are generated (`inspections/<id>/<version>/<category>/<uuid>.<ext>`); user file names are
  metadata only. `LocalStorage.path_for` rejects absolute paths, backslashes, `..` and any key resolving
  outside the storage root. Downloads are served only for keys referenced by DB rows.
* SHA-256 recorded for every input, evidence file and report; `python -m app.maintenance verify` re-checks them.
* ORM-only database access (parameterised); consistent error responses without stack traces.
* CORS limited to configured origins (development additionally allows `localhost:*`).
* Security headers: `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `X-Frame-Options: SAMEORIGIN`.
* Secrets only via environment variables; `.env` is git-ignored; log entries are redacted (passwords,
  tokens, DSN credentials) and never contain image bytes.

Deployment responsibilities (not provided by the dev server):
* TLS termination (reverse proxy) for any non-local access.
* Encryption at rest for the database volume and the evidence storage directory (disk/volume encryption).
* Access control once authentication is added (FastAPI dependencies are the intended integration point).

**Not end-to-end encrypted.** The server must decode image pixels for YOLOv8 and OCR, so inspection
images are processed in plaintext by the backend process and stored (optionally encrypted at rest) in
the storage directory. Components with access to decrypted images: the API/worker process and anyone
with read access to `EAGLEEYE_DATA_DIR`.

Retention: inputs, evidence, reports and versions are kept until explicitly removed; regenerable
thumbnails/temporary fragments are purged by `python -m app.maintenance purge` after
`EAGLEEYE_TEMP_RETENTION_HOURS`.
