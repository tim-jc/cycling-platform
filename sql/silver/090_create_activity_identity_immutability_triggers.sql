-- Foundation identity is append-only. Privileged database administrators may
-- deliberately replace/drop these triggers for governed recovery, but ordinary
-- application DML cannot rewrite or remove established identity.

CREATE OR REPLACE TRIGGER cycling_platform_silver.trg_activity_identity_immutable_update
BEFORE UPDATE ON cycling_platform_silver.activity_identity
FOR EACH ROW
SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Canonical activity identities are immutable';

CREATE OR REPLACE TRIGGER cycling_platform_silver.trg_activity_identity_immutable_delete
BEFORE DELETE ON cycling_platform_silver.activity_identity
FOR EACH ROW
SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Canonical activity identities cannot be deleted';

CREATE OR REPLACE TRIGGER cycling_platform_silver.trg_activity_source_map_immutable_update
BEFORE UPDATE ON cycling_platform_silver.activity_source_map
FOR EACH ROW
SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Canonical activity source mappings are immutable';

CREATE OR REPLACE TRIGGER cycling_platform_silver.trg_activity_source_map_immutable_delete
BEFORE DELETE ON cycling_platform_silver.activity_source_map
FOR EACH ROW
SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Canonical activity source mappings cannot be deleted';
