#!/usr/bin/env python3
"""db/load.py — load run folders into the runs database.

    python3 db/load.py runs.db db/variant-call-cohort.tsv smoke-run-nf cluster-run-nf ...

The tables must exist already (sqlite3 runs.db < db/schema.sql). Each run folder holds
manifest.json and variants.tsv. Each run goes in whole or not at all; a run already in
the database is skipped, so loading twice changes nothing. Standard library only.
"""
import csv
import json
import os
import sqlite3
import sys

SAMPLE_COLUMNS = ["phenotype", "sex", "population", "family", "father", "mother", "run",
                  "read_length", "bases_gb", "study", "native_layout", "library_type",
                  "is_synthetic_phenotype"]


def load_metadata(con, path):
    """The metadata file into samples. Lines starting with # are notes; values are copied as written."""
    with open(path, newline="") as fh:
        lines = [line for line in fh if not line.startswith("#")]
    rows = list(csv.DictReader(lines, delimiter="\t"))
    with con:
        for row in rows:
            sid = row["sample_id"]
            values = [row.get(c) for c in SAMPLE_COLUMNS]
            if con.execute("SELECT 1 FROM samples WHERE sample_id = ?", (sid,)).fetchone():
                con.execute(f"UPDATE samples SET {', '.join(c + ' = ?' for c in SAMPLE_COLUMNS)} "
                            "WHERE sample_id = ?", values + [sid])
            else:
                con.execute(f"INSERT INTO samples (sample_id, {', '.join(SAMPLE_COLUMNS)}) "
                            f"VALUES ({', '.join('?' * (len(SAMPLE_COLUMNS) + 1))})", [sid] + values)
    return len(rows)


def pipeline_id(con, p):
    key = (p["name"], p["version"], p["implementation"])
    row = con.execute("SELECT pipeline_id FROM pipelines WHERE name = ? AND version = ? "
                      "AND implementation = ?", key).fetchone()
    if row:
        return row[0]
    return con.execute("INSERT INTO pipelines (name, version, implementation) VALUES (?, ?, ?)",
                       key).lastrowid


def to_float(text):
    return None if text in ("", ".", None) else float(text)


def load_run(con, folder):
    if not os.path.isfile(os.path.join(folder, "variants.tsv")):
        print(f"{folder}: no variants.tsv, not a run folder this loader reads; skipped")
        return True
    with open(os.path.join(folder, "manifest.json")) as fh:
        m = json.load(fh)
    p, plat, params = m["pipeline"], m.get("platform", {}), m.get("params", {})
    run_id = p["run_id"]
    if con.execute("SELECT 1 FROM runs WHERE run_id = ?", (run_id,)).fetchone():
        print(f"{folder}: run {run_id} is already loaded, skipped")
        return True
    with open(os.path.join(folder, "variants.tsv"), newline="") as fh:
        variants = list(csv.DictReader(fh, delimiter="\t"))
    try:
        with con:                                  # the whole run, or nothing
            pid = pipeline_id(con, p)
            con.execute(
                "INSERT INTO runs (run_id, pipeline_id, started_at, finished_at, exit_status, "
                "platform, executor, engine, git_sha, samplesheet, reference, region, folder) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (run_id, pid, p.get("started_at"), p.get("finished_at"), p.get("exit_status"),
                 plat.get("kind"), plat.get("executor"), plat.get("engine"), p.get("git_sha"),
                 params.get("samplesheet"), params.get("ref"), params.get("region"),
                 os.path.abspath(folder)))
            for s in m["samples"]:
                if not con.execute("SELECT 1 FROM samples WHERE sample_id = ?",
                                   (s["sample_id"],)).fetchone():
                    con.execute("INSERT INTO samples (sample_id) VALUES (?)", (s["sample_id"],))
                # The key (run_id, sample_id) refuses a sample listed twice: the whole run is undone.
                con.execute("INSERT INTO run_samples (run_id, sample_id, condition, library_type) "
                            "VALUES (?, ?, ?, ?)",
                            (run_id, s["sample_id"], s.get("condition"), s.get("library_type")))
            con.executemany(
                "INSERT INTO variants (run_id, chrom, pos, ref, alt, qual, filter) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                [(run_id, v["chrom"], int(v["pos"]), v["ref"], v["alt"], to_float(v["qual"]),
                  v["filter"]) for v in variants])
            con.executemany(
                "INSERT INTO outputs (run_id, path, sha256) VALUES (?, ?, ?)",
                [(run_id, o["path"], o["checksum"].removeprefix("sha256:")) for o in m["outputs"]])
    except sqlite3.IntegrityError as e:
        print(f"{folder}: run {run_id} refused, nothing loaded: {e}", file=sys.stderr)
        return False
    print(f"{folder}: run {run_id} loaded: {len(m['samples'])} samples, "
          f"{len(variants)} variants, {len(m['outputs'])} outputs")
    return True


def main(argv):
    if len(argv) < 3:
        sys.exit("usage: load.py <runs.db> <metadata.tsv> <run folder> [<run folder> ...]")
    db, metadata, folders = argv[0], argv[1], argv[2:]
    con = sqlite3.connect(db)
    con.execute("PRAGMA foreign_keys = ON")       # SQLite checks foreign keys only when asked
    print(f"{metadata}: {load_metadata(con, metadata)} samples")
    ok = all([load_run(con, f) for f in folders])
    con.close()
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
