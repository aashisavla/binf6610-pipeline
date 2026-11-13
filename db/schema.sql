-- db/schema.sql — one database for every run of the variant-call pipeline.
--   sqlite3 runs.db < db/schema.sql
-- Keys do the checking: a repeated run, a row that points at nothing, and the same
-- sample twice in one run are all refused by the database itself.

-- A pipeline version: what ran.
CREATE TABLE pipelines (
    pipeline_id    INTEGER PRIMARY KEY,
    name           TEXT NOT NULL,
    version        TEXT NOT NULL,
    implementation TEXT NOT NULL,              -- nextflow or snakemake
    UNIQUE (name, version, implementation)
) STRICT;

-- One row per run: the facts of its manifest.json, and where its folder is.
CREATE TABLE runs (
    run_id       TEXT PRIMARY KEY,             -- the manifest's pipeline.run_id
    pipeline_id  INTEGER NOT NULL REFERENCES pipelines (pipeline_id),
    started_at   TEXT NOT NULL,
    finished_at  TEXT,
    exit_status  TEXT,
    platform     TEXT,                          -- platform.kind
    executor     TEXT,                          -- platform.executor
    engine       TEXT,                          -- platform.engine
    git_sha      TEXT,
    samplesheet  TEXT,                          -- params.samplesheet
    reference    TEXT,                          -- params.ref
    region       TEXT,                          -- params.region
    folder       TEXT NOT NULL                  -- absolute path of the run's folder
) STRICT;

-- One row per sample: the metadata file's columns, as written there; NULL for a
-- sample the file does not list (the smoke samples).
CREATE TABLE samples (
    sample_id              TEXT PRIMARY KEY,
    phenotype              TEXT,
    sex                    TEXT,
    population             TEXT,
    family                 TEXT,
    father                 TEXT,
    mother                 TEXT,
    run                    TEXT,                -- ENA run accession
    read_length            TEXT,
    bases_gb               TEXT,
    study                  TEXT,
    native_layout          TEXT,
    library_type           TEXT,
    is_synthetic_phenotype TEXT
) STRICT;

-- Which samples each run used, as that run described them.
CREATE TABLE run_samples (
    run_id       TEXT NOT NULL REFERENCES runs (run_id),
    sample_id    TEXT NOT NULL REFERENCES samples (sample_id),
    condition    TEXT,
    library_type TEXT,
    PRIMARY KEY (run_id, sample_id)             -- the same sample twice in a run is refused
) STRICT;

-- One row per line of a run's variants.tsv.
CREATE TABLE variants (
    run_id TEXT NOT NULL REFERENCES runs (run_id),
    chrom  TEXT NOT NULL,
    pos    INTEGER NOT NULL,
    ref    TEXT NOT NULL,
    alt    TEXT NOT NULL,
    qual   REAL,
    filter TEXT
) STRICT;
CREATE INDEX variants_run ON variants (run_id);

-- One row per file in the manifest's outputs, with its sha256 (the 64 hex characters).
CREATE TABLE outputs (
    run_id TEXT NOT NULL REFERENCES runs (run_id),
    path   TEXT NOT NULL,
    sha256 TEXT NOT NULL CHECK (length(sha256) = 64),
    PRIMARY KEY (run_id, path)
) STRICT;
