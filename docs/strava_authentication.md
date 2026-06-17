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

The platform automatically persists the latest refresh token to the project-level `.Renviron` file.

The updated refresh token is used during the next platform execution.

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
