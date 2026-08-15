# Google Health Authentication

## Purpose

This is the owner runbook for initial Google Health OAuth setup, scope changes,
token replacement, and capability validation. The platform uses a long-lived
refresh token to obtain short-lived access tokens for unattended jobs.

The machine-readable scope authority is
`google_health_required_scopes()` in
`R/api/get_google_health_access_token.R`. This document lists the same scopes
for operators but is not the runtime authority.

## Required Scopes

The platform currently requires all three Google Health scopes:

```text
https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly
https://www.googleapis.com/auth/googlehealth.sleep.readonly
https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly
```

They cover:

| Scope family | Platform use |
| --- | --- |
| Health Metrics and Measurements | Heart rate, daily resting heart rate, daily HRV, and daily respiratory rate |
| Sleep | Sleep logs and stages |
| Activity and Fitness | Exercise capability and Raw Exercise ingestion |

Exercise Raw ingestion is implemented as a source-observation object. No Silver
or coaching interpretation exists. The third scope permits both bounded Raw
retrieval and the diagnostic capability probe. Do not add broad scopes such as
`cloud-platform`.

## Credentials and Storage

Three persistent credentials exist:

```text
GOOGLE_HEALTH_CLIENT_ID
GOOGLE_HEALTH_CLIENT_SECRET
GOOGLE_HEALTH_REFRESH_TOKEN
```

Never print, commit, or paste these into tickets, logs, or chat. Access tokens,
authorization codes, refresh tokens, token prefixes, and the client secret are
also sensitive.

### Mac development

The project `.Renviron` contains all three values. The access token is obtained
at runtime and is not stored.

### Production

Development and production do not share a credential file:

| Credential | Host location | Container location |
| --- | --- | --- |
| Static client ID and secret | `~/cycling-infrastructure/compose/.env` | Compose environment |
| Rotating refresh token | `/srv/cycling/config/platform/runtime.Renviron` | `/run/cycling-platform/runtime.Renviron` |

`CYCLING_PLATFORM_RENVIRON_PATH` and `R_ENVIRON_USER` both resolve to the
mounted runtime file inside the container. The host file should be owned by
`tim:tim` with mode `0600`. It may also contain the rotating Strava refresh
token, so edit only `GOOGLE_HEALTH_REFRESH_TOKEN`.

This separation is intentional: ephemeral `docker compose run --rm` jobs must
not lose persistent rotating credentials when their containers are removed.

## Token Flow

```text
stored refresh token
  -> POST https://oauth2.googleapis.com/token
  -> short-lived access token
  -> Google token metadata scope check
  -> Google Health API request
```

Refreshing an access token cannot add scopes. A missing or new scope requires a
fresh browser consent flow and a new refresh token issued to the same OAuth
client used by the platform.

## Adding or Changing Scopes

Scope expansion is complete only after every step below succeeds:

1. Identify the narrow Google Health scope required by the endpoint.
2. Add it to `google_health_required_scopes()` and update tests/documentation.
3. Confirm the Google OAuth app/client is configured to request that scope.
4. Re-authorise, requesting **all required Google Health scopes**, not only the
   new one.
5. Exchange the authorization code and retain the new refresh token.
6. Update the Mac project `.Renviron`.
7. Run the authentication check to prove refresh and granted scopes.
8. Run the capability probe against the new endpoint semantics.
9. Update the production runtime credential file.
10. Run the same authentication and scope check inside the production Compose
    environment.

Do not update production until local refresh, scope validation, and endpoint
capability have all succeeded.

## Generate a Refresh Token with OAuth Playground

### 1. Confirm the OAuth client and redirect URI

Open the [Google APIs Console](https://console.cloud.google.com/apis/credentials),
select the cycling-platform project, then follow the currently observed path:

1. **OAuth consent screen**.
2. **Clients**.
3. **cycling-platform**.
4. Review **Authorised redirect URIs**.

Google may rename or move these controls. Locate the OAuth client details if
the labels have changed. This redirect URI must be present:

```text
https://developers.google.com/oauthplayground
```

OAuth authorization codes can only return to a redirect URI registered for the
client. Playground cannot use the platform client without that entry.

### 2. Configure OAuth Playground

1. Open [OAuth 2.0 Playground](https://developers.google.com/oauthplayground/).
2. Select every scope listed under **Required Scopes** above.
3. Open the Playground configuration using the settings/cog control.
4. Enable **Use your own OAuth credentials**.
5. Enter the existing cycling-platform OAuth Client ID and Client Secret.
6. Do not copy those credentials anywhere else.
7. Click **Authorize APIs**.

Using the platform's own client matters: the resulting refresh token must
belong to the same client ID and secret used by cycling-platform.

### 3. Complete consent

1. Choose the Google account used by cycling-platform.
2. If Google displays **Google hasn't verified this app**, verify that the app
   name and owning project are the cycling-platform app you control.
3. Only in that known-owner situation, choose **Advanced**, then
   **Go to cycling-platform (unsafe)**.
4. Review the requested permissions and confirm that they match the required
   scopes.
5. Click **Continue** and wait for the browser to return to OAuth Playground.

This is not general advice to bypass Google security warnings. Stop if the app,
account, project, permissions, or redirect is unfamiliar.

### 4. Exchange the code

1. In Playground Step 2, confirm an authorization code is present.
2. Click **Exchange authorization code for tokens**.
3. Playground displays an access token and refresh token.
4. Store only the refresh token in the appropriate credential file.
5. Do not store the Playground access token; it is short-lived and the platform
   obtains its own access token from the refresh token.

The browser flow supplies offline consent. Repeating ordinary refresh-token
exchange is not a substitute for re-authorisation and cannot expand scopes.

## Update and Validate Development

Edit the project `.Renviron` with an editor and replace only:

```text
GOOGLE_HEALTH_REFRESH_TOKEN=<new value>
```

Do not place the token in a shell command, where it may enter shell history.
Then run:

```sh
Rscript scripts/google_health/check_authentication.R
```

Success proves that the refresh token works, an access token was obtained, and
all platform-required scopes are granted. It reports the credential-file path,
modification time, credential presence, refresh-token length, and scope names;
it never prints token values or prefixes.

Probe endpoint capability over a bounded window:

```sh
Rscript scripts/google_health/probe_capabilities.R --help
Rscript scripts/google_health/probe_capabilities.R 2026-08-01 2026-08-08
```

The end date is exclusive. Exercise uses interval/session filtering via
`exercise.interval.start_time`; it is deliberately not sent through the generic
sample-time ingestion helper. HTTP success with zero Exercise records proves
access and is reported separately from a permission failure.

## Update and Validate Production

1. Optionally make a protected backup copy of
   `/srv/cycling/config/platform/runtime.Renviron`, but place it outside
   `/srv/cycling/config/platform`. That directory is reserved exclusively for
   the live `runtime.Renviron` and deployment preflight rejects additional
   files. A suitable operator-owned example is
   `~/credential-backups/cycling-platform/` with directory mode `0700` and
   backup-file mode `0600`.
2. Open that file in an editor on `cycling-prod`.
3. Replace only `GOOGLE_HEALTH_REFRESH_TOKEN`; do not alter Strava or other
   credentials.
4. Save, then verify the key exists without displaying its value.
5. Confirm ownership remains `tim:tim` and mode remains `0600`.
6. Use the infrastructure wrapper—not bare `docker compose`—because it supplies
   production UID/GID and runtime environment preparation:

```sh
cd ~/cycling-infrastructure
scripts/compose.sh run --rm cycling-platform \
  Rscript scripts/google_health/check_authentication.R
```

That single command proves production refresh and required-scope validity. To
probe production endpoint capability deliberately, use:

```sh
scripts/compose.sh run --rm cycling-platform \
  Rscript scripts/google_health/probe_capabilities.R 2026-08-01 2026-08-08
```

Do not run the capability probe casually over a large interval.

## What Each Check Proves

| Check | Proves | Does not prove |
| --- | --- | --- |
| `check_authentication.R` | Credential file found; refresh succeeds; access token obtained; every required scope granted | Endpoint contains records; endpoint filter semantics are correct |
| `probe_capabilities.R` | Selected endpoint surfaces accept an authorised request and their endpoint-specific filters; zero records remain distinguishable from access failure | Raw ingestion exists or is correct |
| Raw ingestion | Source retrieval, persistence, lineage, idempotency, and reconciliation for implemented entities, including Exercise source observations | Silver Exercise meaning or coaching use |

## Diagnostics and Common Failures

### `invalid_grant`

The refresh token is expired, revoked, superseded, belongs to the wrong client,
or is otherwise invalid. Repeat the complete Playground flow with the platform
client and all required scopes, then replace and validate the token.

### Refresh succeeds but a required scope is missing

Refreshing preserved the token's old scope grant; it did not add the new scope.
Repeat browser consent requesting all required scopes, exchange for a new
refresh token, update the credential file, and rerun the auth check.

### `DISALLOWED_OAUTH_SCOPES`

Review the requested set against the canonical three scopes. Remove broad or
unrelated scopes such as `cloud-platform`, repeat consent, and validate again.

### Wrong OAuth client or redirect URI

If Playground reports a redirect mismatch, confirm the selected client is
cycling-platform and that its authorised redirect URIs include exactly:

```text
https://developers.google.com/oauthplayground
```

A refresh token generated with different OAuth client credentials will not
work with the platform client ID and secret.

### Scope validation succeeds but an endpoint fails

Run the bounded capability probe. A failure here can indicate an incorrect
data-type name, filter field, interval/sample semantic mismatch, account/API
availability, or endpoint-specific permission—not a refresh problem.

### Testing-mode expiry

Google documents that an external OAuth consent screen in **Testing** normally
issues seven-day refresh tokens when non-basic scopes are requested. Move the
owned app to its intended production publishing status and generate a new token
afterward. A token issued while the app was in Testing should not be assumed to
become durable automatically.

### Other refresh-token invalidation

Google documents revocation, six months of non-use, time-limited access,
administrator policy, and refresh-token issuance limits as possible causes.
Avoid repeatedly generating tokens unnecessarily; store and use the current
valid refresh token persistently.

## Operational Guidance

- Keep the OAuth app out of Testing for normal production use.
- Keep daily ingestion active so the refresh token is used regularly.
- Treat any newly returned refresh token as a rotating persistent credential.
- Never print tokens, prefixes, authorization codes, or the client secret.
- Never commit `.Renviron`, Compose `.env`, or runtime credential files.
- A future scope change must update the canonical R scope set and its tests.

Primary references:

- [Google Health OAuth setup](https://developers.google.com/health/setup)
- [Google OAuth 2.0 overview and refresh-token expiry](https://developers.google.com/identity/protocols/oauth2)
- [Google OAuth offline access and token refresh](https://developers.google.com/identity/protocols/oauth2/web-server)
- [Google OAuth security best practices](https://developers.google.com/identity/protocols/oauth2/resources/best-practices)
