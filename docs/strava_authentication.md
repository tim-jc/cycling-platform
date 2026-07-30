# Strava Authentication

## Overview

The platform uses Strava's OAuth 2.0 refresh token flow to obtain short-lived access tokens.

Long-lived access tokens are never stored.

Authentication is fully automated and requires no user interaction during routine ingestion runs.

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

docker compose run --rm cycling-platform \
  Rscript scripts/bootstrap_strava_oauth.R
```

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
`/run/cycling-platform/runtime.Renviron`. Compose bind-mounts that path from
`/srv/cycling/config/platform/runtime.Renviron` on the host.

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
docker compose run --rm cycling-platform \
  Rscript platform.R manual --no-notification

docker compose run --rm cycling-platform \
  Rscript run_silver.R repair
```

Inspect the gear entity in the Raw notification/Admin run metadata and run the
documented gear-resolution audit if any activity IDs remain unresolved.

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
