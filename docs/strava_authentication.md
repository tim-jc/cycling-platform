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

## Token Rotation

Strava refresh tokens rotate after every successful token exchange.

The platform automatically persists the latest refresh token to the path
resolved from `CYCLING_PLATFORM_RENVIRON_PATH`, `R_ENVIRON_USER`, or the
project-level `.Renviron`.

The updated refresh token is used during the next platform execution.

In production, that path must be a persistent writable file or mount. Writing a
rotated token only inside an ephemeral `docker compose run --rm` container is
not sufficient because the file disappears with the container. The production
Compose credential-persistence arrangement is maintained outside this
repository and must be verified after deployment changes.

## Secrets Management

The following values are stored in `.Renviron` and must never be committed to source control:

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
