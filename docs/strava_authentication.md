# Strava Authentication

## Overview

The platform uses Strava's OAuth 2.0 refresh token flow to obtain short-lived access tokens.

Long-lived access tokens are never stored.

Authentication is fully automated and requires no user interaction during routine ingestion runs.

The browser-based bootstrap is an exceptional administrative action used for
initial authorisation, recovery after revocation, or a scope change. Routine
automation must use the refresh-token flow.

## Credential and Authorisation Lifecycle

| Item | Purpose | Lifetime and handling |
| --- | --- | --- |
| `STRAVA_CLIENT_ID` | Identifies the registered application | Application configuration; not a bearer credential |
| `STRAVA_CLIENT_SECRET` | Authenticates the application to the token endpoint | Long-lived secret; rotate through Compose configuration |
| User authorisation | Athlete approval of the requested scopes | Must be repeated when scopes expand or access is revoked |
| Authorisation code | One-time code returned in the browser redirect | Short-lived and single-use; paste only into the bootstrap prompt |
| Access token | Authorises API requests | Short-lived and held only for the current process |
| Refresh token | Obtains later access tokens | Rotates during exchange and must be persisted after every successful refresh |
| Granted scopes | Permissions attached to the user authorisation | Validated against the canonical required scopes before bootstrap persists a token |

The application credentials do not grant access by themselves. The athlete
authorises the application, Strava returns a one-time code, and the bootstrap
helper exchanges that code for access and refresh tokens. Later scheduled runs
exchange the persisted refresh token for a short-lived access token and persist
any rotated refresh token. A refresh exchange cannot add permissions: a new
scope always requires browser re-authorisation.

## Authentication Flow

```text
STRAVA_REFRESH_TOKEN
        ↓
POST /oauth/token
        ↓
access_token
refresh_token
expires_at
        ↓
Persist latest refresh_token
        ↓
GET /athlete/activities
```

## Token Endpoint

```text
https://www.strava.com/oauth/token
```

## Request Parameters

| Parameter       | Value                  |
| --------------- | ---------------------- |
| `client_id`     | `STRAVA_CLIENT_ID`     |
| `client_secret` | `STRAVA_CLIENT_SECRET` |
| `refresh_token` | `STRAVA_REFRESH_TOKEN` |
| `grant_type`    | `refresh_token`        |

## Expected Response

| Field           | Description                                    |
| --------------- | ---------------------------------------------- |
| `access_token`  | Short-lived bearer token used for API requests |
| `refresh_token` | Token used to obtain future access tokens      |
| `expires_at`    | Access token expiry timestamp                  |
| `expires_in`    | Access token lifetime in seconds               |
| `scope`         | Granted API permissions                        |

## Required Scopes

* `read`
* `activity:read_all`
* `profile:read_all` (required for the detailed authenticated-athlete gear
  collection used by Strava gear ingestion)

The individual `GET /gear/{id}` endpoint uses the existing bearer token.
`GET /athlete` returns a detailed athlete only when `profile:read_all` is
granted; the gear loader fails clearly rather than treating an omitted
`bikes`/`shoes` collection as an authoritative empty snapshot.

## Initial Authorisation and Scope Expansion

A refresh-token exchange cannot add scopes. Run the interactive bootstrap
helper for the first authorisation or whenever the required scope set expands.
It generates a Strava authorisation URL requesting every scope listed above,
forces the consent screen to be shown, and validates the scopes granted in both
the browser redirect and token response.

The helper prompts for the **complete redirect URL**, not a command-line
argument. The URL contains the short-lived, single-use authorisation code and
the granted scopes. Paste it into the helper's standard-input prompt and press
Enter. The pasted URL may be visible in the terminal because standard input is
echoed, but it is not entered as a shell command and is therefore not written
to shell history.

For future interactive `Rscript` helpers, use the same lightweight CLI
convention: print and flush the prompt, then read one required line from the
real process standard input. Do not gate input on `interactive()` or use a
password-prompt helper where terminal echo is explicitly acceptable; those
approaches may return immediately in ephemeral Docker jobs.

For an initial setup:

1. Register or inspect the application at
   <https://www.strava.com/settings/api>.
2. Confirm its callback domain permits the redirect URI described below.
3. Configure `STRAVA_CLIENT_ID` and `STRAVA_CLIENT_SECRET` in Compose without
   putting either value on the command line.
4. Create the host runtime file if it does not exist, restrict its permissions,
   and confirm the container sees it at the mounted path below.
5. Run the helper, approve all three scopes, and paste the complete redirect
   URL into its standard-input prompt.

For scope expansion, repeat the same consent flow. Do not attempt to add scopes
to the refresh request: refresh-token exchange can only preserve the scopes
already granted. The helper validates both the redirect and token response
before replacing the stored refresh token.

In the production ephemeral Compose container:

```bash
cd ~/cycling-infrastructure/compose

docker compose run --rm -i cycling-platform \
  Rscript scripts/bootstrap_strava_oauth.R
```

`-i` keeps standard input attached to the one-off container so the R process
can block while it reads the pasted redirect URL. `-T` is not required by this
workflow. Omitting `-i` can produce `No Strava redirect URL was supplied`
because the helper receives end-of-file immediately.

Open the URL printed by the helper, approve every requested permission, then
paste the complete URL from the browser after Strava redirects to
`http://localhost`. The browser may report that it cannot connect; that is
expected because the redirect URL is being copied back to the helper rather
than handled by a local web server.

The helper defaults `STRAVA_REDIRECT_URI` to `http://localhost`. Before running
it, confirm the Strava application at <https://www.strava.com/settings/api>
allows the `localhost` callback domain. Strava explicitly permits `localhost`
and `127.0.0.1` for this manual flow. If the registered application deliberately
uses another callback domain, configure `STRAVA_REDIRECT_URI` to a URI within
that domain and paste the redirect for that exact URI; the helper rejects a
redirect from any other scheme, host, port, or path.

`STRAVA_CLIENT_ID` and `STRAVA_CLIENT_SECRET` must already be available in the
container. The persistent runtime credential file must exist, be writable, and
be selected by both `CYCLING_PLATFORM_RENVIRON_PATH` and `R_ENVIRON_USER` as
`/run/cycling-platform/runtime.Renviron`. Production Compose bind-mounts that
path read-write from the environment-specific host path
`/srv/cycling/config/platform/runtime.Renviron`.

`R_ENVIRON_USER` makes R load the mounted file at process startup.
`CYCLING_PLATFORM_RENVIRON_PATH` tells the application's persistence helper
where to write rotated credentials. They intentionally resolve to the same
file. `update_renviron()` replaces only the named key and preserves unrelated
lines such as `GOOGLE_HEALTH_REFRESH_TOKEN`; direct writes from endpoint code
would bypass that contract.

The host file should be owned by the account that runs Compose, writable by the
container process, unreadable by other users where practical, and backed up
through the infrastructure secret-recovery process. Host directory creation,
mount definitions, ownership, and permissions belong to
`cycling-infrastructure`, not this application repository.

Confirm paths and the presence of variables without displaying values:

```bash
docker compose config --quiet

docker compose run --rm cycling-platform Rscript -e '
cat("R_ENVIRON_USER=", Sys.getenv("R_ENVIRON_USER"), "\n", sep = "")
cat("CYCLING_PLATFORM_RENVIRON_PATH=", Sys.getenv("CYCLING_PLATFORM_RENVIRON_PATH"), "\n", sep = "")
cat("runtime file exists=", file.exists(Sys.getenv("R_ENVIRON_USER")), "\n", sep = "")
cat("runtime file writable=", file.access(Sys.getenv("R_ENVIRON_USER"), 2) == 0, "\n", sep = "")
cat("STRAVA_REFRESH_TOKEN=", if (nzchar(Sys.getenv("STRAVA_REFRESH_TOKEN"))) "set" else "MISSING", "\n", sep = "")
'
```

On success, the helper updates only `STRAVA_REFRESH_TOKEN` through
`update_renviron()`. Other entries, including `GOOGLE_HEALTH_REFRESH_TOKEN`,
are preserved. The helper does not print the access token, refresh token,
client secret, authorisation code, or pasted redirect URL.

After authorisation, prove that a new ephemeral container reads the persisted
token without displaying it:

```bash
docker compose run --rm cycling-platform Rscript -e '
cat(
  "STRAVA_REFRESH_TOKEN",
  if (nzchar(Sys.getenv("STRAVA_REFRESH_TOKEN"))) "set\n" else "MISSING\n"
)
'
```

Then run Raw ingestion and Silver publication manually before relying on the
next scheduled run:

```bash
# PRODUCTION WRITE: incremental Raw ingestion, including gear.
docker compose run --rm cycling-platform \
  Rscript platform.R manual --no-notification

# PRODUCTION WRITE: deterministic Silver repair; runs all Silver transforms.
docker compose run --rm cycling-platform \
  Rscript run_silver.R repair

# Publication-scope validation; records validation metadata and can notify.
docker compose run --rm cycling-platform \
  Rscript run_platform_validation.R --publication
```

Inspect the gear entity in the Raw notification/Admin run metadata and run the
documented gear-resolution audit if any activity IDs remain unresolved.

## Bootstrap Happy Path

1. Confirm the registered Strava callback domain and the intended
   `STRAVA_REDIRECT_URI` (default `http://localhost`).
2. Confirm the canonical scopes above are still correct.
3. Confirm the Compose configuration, mounted runtime path, file existence, and
   writability using the safe diagnostics above.
4. Rebuild the application image. The helper is copied into the image; pulling
   source alone does not update it.
5. Run `docker compose run --rm -i cycling-platform Rscript
   scripts/bootstrap_strava_oauth.R`.
6. Open the printed authorisation URL and approve every requested permission.
7. Paste the complete redirect URL at the prompt. It may be visible in the
   terminal, but because it is input to the running process it is not written
   as a shell-history command. Never copy it into logs, tickets, or docs.
8. Confirm the helper reports validated scopes and successful persistence. It
   must not display the client secret, code, access token, refresh token, or
   pasted URL.
9. Start a new ephemeral container and use the safe set/MISSING check above.
10. Run controlled Raw, Silver, and publication validation before accepting the
    next scheduled run.

The helper generates a cryptographically random OAuth state, requires the
redirect URI to match exactly, validates state and scopes, uses
`grant_type=authorization_code`, validates the complete token response, and
only then persists `STRAVA_REFRESH_TOKEN`. Any failure exits non-zero without
changing the credential file.

## Recovery Matrix

Do not delete the complete runtime credential file as a generic response to a
token failure.

| Symptom | Safe diagnosis | Corrective action |
| --- | --- | --- |
| Refresh token missing | Use the set/MISSING check in a new container; check the two configured paths and mount existence | Restore the token through the approved secret-recovery process or complete bootstrap |
| `invalid_grant`, expired, or revoked refresh token | Confirm paths and that a token is present; do not print it | Re-authorise with the bootstrap helper and then verify persistence |
| Required scope missing | Compare the error's required, granted, and missing scope names | Re-authorise and approve every scope; refresh exchange cannot add one |
| Client secret rotated | Confirm the Compose variable is set by name only and rebuild/recreate the job environment | Update the infrastructure-managed secret, validate Compose, then retry with a fresh authorisation code if needed |
| Redirect URI mismatch | Compare `STRAVA_REDIRECT_URI` with the registered callback domain and the URL named in the error | Correct the configuration or registration; restart bootstrap rather than editing the returned URL |
| State mismatch | Treat the redirect as belonging to another or stale bootstrap session | Discard it and restart the helper; never bypass state validation |
| `access_denied` | Confirm the user rejected or cancelled consent | Restart only when ready to approve all required scopes |
| Blank input or stdin EOF | Confirm the command used `docker compose run --rm -i` | Restart the helper with stdin attached and paste one complete line |
| Authorisation succeeds but persistence fails | Check the mounted path exists and is writable; do not reuse or log the code | Fix ownership/mount configuration, then restart bootstrap because the code is single-use |
| Host file updated but a new container reports MISSING | Inspect both selector paths, Compose mount source/target, and file permissions | Correct the infrastructure wiring and recreate the container; do not copy tokens via command-line arguments |

Errors and diagnostics may include status codes, scope names, paths, and
set/MISSING state. They must never include client secrets, redirect URLs,
authorisation codes, access tokens, or refresh-token values.

## Token Rotation

Strava refresh tokens rotate after every successful token exchange.

The platform automatically persists the latest refresh token to the path
resolved from `CYCLING_PLATFORM_RENVIRON_PATH`, `R_ENVIRON_USER`, or the
project-level `.Renviron`.

The updated refresh token is used during the next platform execution.

In production, `/run/cycling-platform/runtime.Renviron` is a writable bind mount
backed by `/srv/cycling/config/platform/runtime.Renviron`. Writing anywhere else
inside an ephemeral `docker compose run --rm` container will be lost. Verify
both selector variables and the mount after Compose changes.

## Secrets Management

The following values are stored outside source control and must never be
committed:

* `STRAVA_CLIENT_ID`
* `STRAVA_CLIENT_SECRET`
* `STRAVA_REFRESH_TOKEN`

A corresponding `.Renviron.example` file should be maintained without values.

The runtime file is a secret-bearing operational artefact, not application
source. Never pass its values as command-line arguments, paste them into a
ticket, use a diagnostic that prints the environment, or commit the file.

## Container Troubleshooting

When repository behaviour and production behaviour differ:

```bash
# Confirm the packaged helper exists and inspect non-secret source text.
docker compose run --rm --entrypoint sh cycling-platform -c \
  'ls -l scripts/bootstrap_strava_oauth.R R/api/bootstrap_strava_oauth.R'

# Show the image attached to the service and its creation metadata.
docker compose images cycling-platform
docker image inspect cycling-platform:dev \
  --format 'id={{.Id}} created={{.Created}}'

# Prove that one stdin line reaches R without involving OAuth.
printf 'stdin-check\n' | docker compose run --rm -i cycling-platform \
  Rscript -e 'x <- readLines(file("stdin", "r"), n = 1L); cat(length(x), "\n")'

# Rebuild after application source changed.
docker compose build cycling-platform
```

The minimal stdin probe proves process wiring only; it does not prove that a
particular helper reads stdin correctly. Non-interactive `Rscript` differs from
an interactive R session, so prompt code must read process stdin explicitly.
Using `--entrypoint` can isolate wrapper or image problems, but it is a
diagnostic technique rather than the normal bootstrap procedure. Inspecting the
packaged file is often the fastest way to identify a stale image.

## Design Principles

* Access tokens are ephemeral.
* Refresh tokens are treated as secrets.
* Authentication is non-interactive.
* Secrets are externalised.
* Token refresh is automatic.
* Credential rotation is transparent to ingestion workflows.

## Rate Limit Handling

Strava rate-limit handling is centralised in `perform_strava_request()`.
Successful responses log the `x-ratelimit-limit` and `x-ratelimit-usage`
headers.

Historical ingestion showed a practical 15-minute cap of around 100 requests,
even where the public app quota header reported 200. The request helper
therefore sleeps proactively at 95 requests in the current 15-minute window and
allows one request after waking so fresh headers can be read.
