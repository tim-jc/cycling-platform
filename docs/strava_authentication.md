Flow:

STRAVA_REFRESH_TOKEN
        ↓
POST /oauth/token
        ↓
access_token
        ↓
GET /athlete/activities

Endpoint:

https://www.strava.com/api/v3/oauth/token

Expected inputs:

client_id
client_secret
refresh_token
grant_type = refresh_token

Expected output:

access_token
expires_at
