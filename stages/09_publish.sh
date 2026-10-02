#!/usr/bin/env bash
# stage 9 — publish: copy the deliverables into results/ and write manifest.json.
set -euo pipefail

stage_publish() {
    # results/ holds only what the run publishes; write_manifest.sh checksums every file in it.
    local vcf=$OUT/07_analyze/cohort.filtered.vcf.gz
    RES=$OUT/results
    mkdir -p "$RES"
    need_file "$vcf" publish
    cp "$vcf" "$vcf.tbi" "$RES/"
    cp "$OUT/08_qc_report/multiqc_report.html" "$RES/"
    log "publish: writing $RES/manifest.json"
    bash "${HERE}/lib/write_manifest.sh" "${RES}" "${SHEET}" "${REF}" "${REGION}" >&2
    need_file "$RES/manifest.json" publish
}
