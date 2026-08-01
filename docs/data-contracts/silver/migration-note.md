# Silver contract migration note

The original Silver drafts combined semantic prose and generated column catalogues in Markdown and stored generated JSON beside documentation. The governance framework preserves useful semantic observations while moving physical schema, lineage, quality references and structured TODO state to `metadata/silver/`.

Mechanical column tables were removed from Markdown to avoid a second authority. Repository DDL now generates those fields, and the validator checks the committed metadata against DDL. Uncertainty from the drafts remains visible as structured open TODOs rather than being replaced with inferred meaning.
