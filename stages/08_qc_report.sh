#!/usr/bin/env bash
# stage 8 — qc_report: one MultiQC report across the cohort.
set -euo pipefail

stage_qc_report() {
    local d=$OUT/08_qc_report
    mkdir -p "$d"
    multiqc -f -o "$d" "$OUT/01_qc_raw" "$OUT/02_trim" "$OUT/04_postprocess" >&2
    need_file "$d/multiqc_report.html" qc_report
}
