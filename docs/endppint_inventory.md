| Entity            | Endpoint                    | Raw Table              | Priority | Incremental | Status   | Notes                     |
|-------------------|-----------------------------|------------------------|----------|--------------|----------|---------------------------|
| Activities        | `/athlete/activities`       | `raw.activities`       | High     | Yes          | Planned  | Core activity metadata    |
| Activity Streams  | `/activities/{id}/streams`  | `raw.activity_streams` | High     | Conditional  | Planned  | Depends on activities     |
| Athlete           | `/athlete`                  | `raw.athlete`          | High     | No           | Planned  | Current athlete snapshot  |
| Gear              | `/gear/{id}`                | `raw.gear`             | Medium   | No           | Planned  | Retrieved from activities |
| Routes            | `/routes/{id}`              | `raw.routes`           | Low      | No           | Planned  | On-demand enrichment      |
| Zones             | `/athlete/zones`            | `raw.zones`            | Medium   | No           | Planned  | Training zones            |