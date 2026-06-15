Create etl_run
        ↓
Discover entities to ingest
        ↓
For each entity:

    Create etl_run_entity
            ↓
    Extract
            ↓
    Load raw
            ↓
    Update etl_run_entity

        ↓
Complete etl_run
        ↓
Send notification