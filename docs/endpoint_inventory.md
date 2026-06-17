| Entity           | Endpoint                   | Raw Table              | Business Key                 | Priority | Refresh Strategy              | Status     | Notes                              |
| ---------------- | -------------------------- | ---------------------- | ---------------------------- | -------- | ----------------------------- | ---------- | ---------------------------------- |
| Activities       | `/athlete/activities`      | `raw.activities`       | `activity_id`                | High     | Rolling window + hygiene runs | API tested | Core activity metadata             |
| Activity Streams | `/activities/{id}/streams` | `raw.activity_streams` | `activity_id`, `stream_type` | High     | Conditional                   | Planned    | Retrieved for selected activities  |
| Athlete          | `/athlete`                 | `raw.athlete`          | `athlete_id`                 | High     | Full refresh                  | Planned    | Current athlete snapshot           |
| Gear             | `/gear/{id}`               | `raw.gear`             | `gear_id`                    | Medium   | On demand                     | Planned    | Retrieved from activity references |
| Routes           | `/routes/{id}`             | `raw.routes`           | `route_id`                   | Low      | On demand                     | Planned    | Optional route enrichment          |
| Zones            | `/athlete/zones`           | `raw.zones`            | `athlete_id`                 | Medium   | Full refresh                  | Planned    | Training zones snapshot            |
