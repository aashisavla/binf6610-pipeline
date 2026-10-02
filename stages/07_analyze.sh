#!/usr/bin/env bash
# stage 7 — analyze: GATK Best Practices hard filters, SNPs and indels separately.
set -euo pipefail

stage_analyze() {
    local d=$OUT/07_analyze in=$OUT/06_merge/cohort.vcf.gz out total pass
    out=$d/cohort.filtered.vcf.gz
    mkdir -p "$d"

    gatk_ SelectVariants -R "$REF" -V "$in" --select-type-to-include SNP -O "$d/snps.vcf.gz"
    gatk_ SelectVariants -R "$REF" -V "$in" --select-type-to-include INDEL \
          --select-type-to-include MIXED -O "$d/indels.vcf.gz"

    # VariantFiltration tags FILTER; it removes nothing.
    gatk_ VariantFiltration -R "$REF" -V "$d/snps.vcf.gz" -O "$d/snps.filtered.vcf.gz" \
        --filter-expression "QD < 2.0"              --filter-name QD2 \
        --filter-expression "FS > 60.0"             --filter-name FS60 \
        --filter-expression "MQ < 40.0"             --filter-name MQ40 \
        --filter-expression "SOR > 3.0"             --filter-name SOR3 \
        --filter-expression "MQRankSum < -12.5"     --filter-name MQRankSum-12.5 \
        --filter-expression "ReadPosRankSum < -8.0" --filter-name ReadPosRankSum-8
    gatk_ VariantFiltration -R "$REF" -V "$d/indels.vcf.gz" -O "$d/indels.filtered.vcf.gz" \
        --filter-expression "QD < 2.0"               --filter-name QD2 \
        --filter-expression "FS > 200.0"             --filter-name FS200 \
        --filter-expression "ReadPosRankSum < -20.0" --filter-name ReadPosRankSum-20

    gatk_ MergeVcfs -I "$d/snps.filtered.vcf.gz" -I "$d/indels.filtered.vcf.gz" -O "$out"
    need_file "$out" analyze

    total=$(count_records "$out")
    pass=$(gzip -dc "$out" | awk -F'\t' '!/^#/ && $7 == "PASS" {n++} END {print n+0}')
    log "analyze: $total records, $pass PASS"
    log "analyze: sample columns: $(gzip -dc "$out" | awk -F'\t' '/^#CHROM/ {for (i = 10; i <= NF; i++) printf "%s ", $i; exit}')"
}
