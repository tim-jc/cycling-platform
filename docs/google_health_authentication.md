# Google Health Authentication

## Overview

The platform uses Google OAuth 2.0 refresh-token flow to obtain short-lived
access tokens for Google Health API requests.

Access tokens are ephemeral. The long-lived credential is
`GOOGLE_HEALTH_REFRESH_TOKEN`, stored in the project `.Renviron`.

## Required Scopes

The current platform requires both scopes:

```text
https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly
https://www.googleapis.com/auth/googlehealth.sleep.readonly
```

They are required because the platform ingests:

* heart-rate samples;
* daily resting heart rate;
* daily heart-rate variability;
* daily respiratory rate;
* sleep logs, including sleep-stage metadata retained in the payload.

If a refresh token is generated with only one scope, token refresh may succeed
but one or more endpoints can fail with a scope or permission error.

## Secrets

The following values are stored in `.Renviron` and must never be committed:

```text
GOOGLE_HEALTH_CLIENT_ID=...
GOOGLE_HEALTH_CLIENT_SECRET=...
GOOGLE_HEALTH_REFRESH_TOKEN=1//...
```

## Token Flow

```text
GOOGLE_HEALTH_REFRESH_TOKEN
        ↓
POST https://oauth2.googleapis.com/token
        ↓
access_token
        ↓
GET https://health.googleapis.com/v4/users/me/dataTypes/{dataType}/dataPoints
```

Google generally does not rotate refresh tokens on every access-token refresh.
If Google does return a new refresh token, the platform writes it back to
`.Renviron`.

Routine cron wrappers run from a temporary project copy. They copy `.Renviron`
into that runtime directory so macOS cron can read it, then copy it back to the
project if a refresh-token update changes the runtime file.

## Token Lifetime

Google refresh tokens can stop working. Common causes include:

* user revocation;
* the token not being used for six months;
* too many refresh tokens for the same Google account and OAuth client;
* time-based access expiry;
* admin/session policies;
* OAuth consent screen in `Testing` publishing status.

For an external Google Cloud OAuth app in `Testing`, Google issues refresh
tokens that expire after seven days for non-basic scopes. Google Health scopes
are not basic profile/email scopes, so weekly expiry is expected unless the app
can be moved to `Production`.

## Regenerating a Refresh Token

Regenerate the token when:

* auth check fails with `invalid_grant`;
* the token was generated before all required scopes were requested;
* Google reports missing or disallowed scopes;
* the Google Cloud OAuth client or consent configuration changes.

The consent request must include:

```text
access_type=offline
prompt=consent
```

and both required scopes:

```text
https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly
https://www.googleapis.com/auth/googlehealth.sleep.readonly
```

After completing consent, paste the returned refresh token into `.Renviron`:

```text
GOOGLE_HEALTH_REFRESH_TOKEN=1//...
```

Then validate:

```sh
Rscript run_google_health_auth_check.R
```

Expected successful output includes:

```text
Google Health refresh succeeded
Google Health access token refresh succeeded
```

It is normal for the refresh response to say:

```text
response did not include a new refresh token
```

## Diagnostics

Run:

```sh
Rscript run_google_health_auth_check.R
```

The check reports:

* token file path;
* token file modification time;
* whether client id, client secret and refresh token are present;
* refresh token length and prefix;
* whether refresh succeeds.

It never prints the full refresh token.

During unattended automation, `platform.R` performs a Google Health token
preflight before any ingestion work when Google Health is enabled. A bad token
therefore fails fast before Strava ingestion and derived transforms run.

## Common Failures

### `invalid_grant`

The refresh token is expired, revoked, superseded, or no longer valid for the
OAuth client and scope set.

Action:

1. Regenerate the refresh token with both required scopes.
2. Replace `GOOGLE_HEALTH_REFRESH_TOKEN` in `.Renviron`.
3. Run `Rscript run_google_health_auth_check.R`.

### `DISALLOWED_OAUTH_SCOPES`

The access token includes a scope that Google Health does not allow for the
current endpoint or app configuration.

Action:

1. Regenerate the token using only the required Google Health scopes above.
2. Do not include broad scopes such as `cloud-platform`.
3. Rerun the auth check.

### Scope/permission errors after refresh succeeds

The token is valid but was not granted all endpoint scopes.

Action:

1. Regenerate with both required scopes.
2. Confirm the consent screen presented both scopes.
3. Rerun a short Google Health capability probe if endpoint access is still
   uncertain.

## Operational Guidance

To avoid unnecessary manual regeneration:

* move the OAuth consent screen out of `Testing` if Google permits it for this
  project and scope set;
* avoid repeatedly generating new refresh tokens for the same Google account
  and OAuth client;
* keep the daily platform run active so the token is used regularly;
* keep the required scopes stable unless the Raw ingestion surface changes.
