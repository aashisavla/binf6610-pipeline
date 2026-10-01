#!/usr/bin/env bash
# run_pipeline.sh — ten-stage germline variant-calling pipeline (BINF6610, assignment 1)
#
# usage:  run_pipeline.sh <samplesheet.csv> <outdir> [last_stage]
# stages: validate qc_raw trim align postprocess quantify merge analyze qc_report publish
#
# The samplesheet is the only per-sample input. Only REF and REGION change between
# the laptop smoke run and the Explorer cohort run:
#   cd smoke && REF=$PWD/smoke.fa REGION=smoke_1mb bash ~/repo/run_pipeline.sh samplesheet.csv ~/smoke-out
#
# Written for bash 3.2 (macOS /bin/bash) as well as bash 4/5: no associative arrays,
# no mapfile, no ${x,,}, and no "${arr[@]}" expansion of a possibly-empty array.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}
THREADS=${THREADS:-4}
JAVA_MEM=${JAVA_MEM:-3g}

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

# ---------------------------------------------------------------- helpers
# Everything human-readable goes to stderr; stdout stays empty.
log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
need_file() { if [[ ! -s $1 ]]; then die "$2: expected output missing or empty: $1"; fi; }
gatk_() { gatk --java-options "-Xmx${JAVA_MEM}" "$@" >&2; }
lc()   { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
trim() { local s=$1; s=${s#"${s%%[![:space:]]*}"}; s=${s%"${s##*[![:space:]]}"}; printf '%s' "$s"; }
count_records() { gzip -dc "$1" | awk '!/^#/ {n++} END {print n+0}'; }

usage() {
    printf 'usage: %s <samplesheet.csv> <outdir> [last_stage]\nstages: %s\n' "$0" "${STAGES[*]}" >&2
    exit 2
}

# ---------------------------------------------------------------- arguments
if [[ $# -lt 2 || $# -gt 3 ]]; then usage; fi
SHEET=$1
OUTARG=$2
LAST=${3:-publish}

LAST_IDX=-1
for ((s = 0; s < ${#STAGES[@]}; s++)); do
    if [[ ${STAGES[s]} == "$LAST" ]]; then LAST_IDX=$s; fi
done
if (( LAST_IDX < 0 )); then die "unknown stage '$LAST' (expected one of: ${STAGES[*]})"; fi

# ---------------------------------------------------------------- samplesheet
# Parallel arrays, one entry per row. Filled by load_sheet, used by every stage.
IDS=(); R1S=(); R2S=(); LIBS=(); CONDS=()
ERRORS=()
err() { ERRORS+=("$*"); }

# A relative FASTQ path is taken relative to the current directory (the README's
# "run from inside smoke/"); failing that, relative to the samplesheet's folder.
resolve() {
    local p=$1
    if [[ -z $p || $p == /* || -e $p ]]; then printf '%s' "$p"
    elif [[ -e $SHEET_DIR/$p ]]; then printf '%s' "$SHEET_DIR/$p"
    else printf '%s' "$p"; fi
}

load_sheet() {
    if [[ ! -f $SHEET ]]; then die "samplesheet not found: $SHEET"; fi
    SHEET_DIR=$(cd "$(dirname "$SHEET")" && pwd)

    local header line rowno=0 i name lib
    local c_id=-1 c_r1=-1 c_r2=-1 c_lib=-1 c_cond=-1
    local -a cols f

    if ! IFS= read -r header < "$SHEET"; then die "samplesheet is empty: $SHEET"; fi
    header=${header%$'\r'}
    IFS=, read -r -a cols <<< "$header"
    for ((i = 0; i < ${#cols[@]}; i++)); do
        name=$(lc "$(trim "${cols[i]}")")
        case $name in
            sample_id)    c_id=$i ;;
            r1_fastq)     c_r1=$i ;;
            r2_fastq)     c_r2=$i ;;
            library_type) c_lib=$i ;;
            condition)    c_cond=$i ;;
        esac
    done
    if (( c_id < 0 || c_r1 < 0 || c_r2 < 0 || c_lib < 0 )); then
        die "samplesheet header must contain sample_id, r1_fastq, r2_fastq, library_type; got: $header"
    fi

    while IFS= read -r line || [[ -n $line ]]; do
        rowno=$((rowno + 1))
        if (( rowno == 1 )); then continue; fi              # header
        line=${line%$'\r'}                                  # tolerate CRLF
        if [[ -z ${line//[[:space:],]/} ]]; then continue; fi  # blank row
        IFS=, read -r -a f <<< "$line"

        lib=$(lc "$(trim "${f[c_lib]:-}")")
        case $lib in
            paired|pe|paired-end|paired_end) lib=paired ;;
            single|se|single-end|single_end) lib=single ;;
        esac

        IDS+=("$(trim "${f[c_id]:-}")")
        R1S+=("$(resolve "$(trim "${f[c_r1]:-}")")")
        R2S+=("$(resolve "$(trim "${f[c_r2]:-}")")")
        LIBS+=("$lib")
        if (( c_cond >= 0 )); then CONDS+=("$(trim "${f[c_cond]:-}")"); else CONDS+=("NA"); fi
    done < "$SHEET"
}

# ---------------------------------------------------------------- stage 0
check_fastq() {   # <sample_id> <R1|R2> <path>  -> 0 if the file is a complete gzip
    local id=$1 label=$2 f=$3
    if [[ -z $f ]];   then err "sample '$id': $label path is empty"; return 1; fi
    if [[ ! -f $f ]]; then err "sample '$id': $label file not found: $f"; return 1; fi
    if [[ ! -s $f ]]; then err "sample '$id': $label file is empty: $f"; return 1; fi
    if ! gzip -t "$f" 2>/dev/null; then
        err "sample '$id': $label is not a complete gzip stream (truncated or corrupt): $f"
        return 1
    fi
    return 0
}

stage_validate() {
    load_sheet
    local n=${#IDS[@]} i j id lib r1 r2 c1 c2 ok1 ok2 ext dict tool

    if (( n == 0 )); then err "samplesheet has no sample rows: $SHEET"; fi

    for ((i = 0; i < n; i++)); do
        id=${IDS[i]}; r1=${R1S[i]}; r2=${R2S[i]}; lib=${LIBS[i]}
        log "stage 0: checking sample '$id' ($lib)"

        if [[ -z $id ]]; then err "row $((i + 2)): empty sample_id"; continue; fi
        if [[ $id == */* ]]; then err "sample '$id': sample_id must not contain '/'"; fi
        for ((j = 0; j < i; j++)); do
            if [[ ${IDS[j]} == "$id" ]]; then
                err "sample '$id': duplicate sample_id (rows $((j + 2)) and $((i + 2)))"
            fi
        done

        case $lib in
            paired)
                if [[ -z $r2 ]]; then err "sample '$id': library_type is paired but r2_fastq is empty"; fi ;;
            single)
                if [[ -n $r2 ]]; then
                    log "stage 0: WARNING sample '$id' is single-end; ignoring r2_fastq"
                    R2S[i]=""; r2=""
                fi ;;
            *)
                err "sample '$id': unrecognised library_type '${LIBS[i]}' (expected paired or single)" ;;
        esac

        ok1=0; ok2=0
        if check_fastq "$id" R1 "$r1"; then ok1=1; fi
        if [[ $lib == paired && -n $r2 ]]; then
            if check_fastq "$id" R2 "$r2"; then ok2=1; fi
        fi

        # Assert on the data, not just on exit codes.
        if (( ok1 )); then
            c1=$(gzip -dc "$r1" | wc -l | tr -d ' ')
            if (( c1 == 0 )); then err "sample '$id': R1 contains no reads: $r1"
            elif (( c1 % 4 != 0 )); then err "sample '$id': R1 has $c1 lines, not a multiple of 4: $r1"; fi
            if (( ok2 )); then
                c2=$(gzip -dc "$r2" | wc -l | tr -d ' ')
                if (( c1 != c2 )); then err "sample '$id': R1 has $((c1 / 4)) reads but R2 has $((c2 / 4))"; fi
            fi
        fi
    done

    # Reference and tools are checked only when the run goes past stage 0, so
    # `... validate` works on a laptop where the Explorer REF does not exist.
    if (( LAST_IDX > 0 )); then
        if [[ ! -f $REF ]]; then err "reference not found: $REF (set REF=...)"
        else
            for ext in .fai .bwt; do
                if [[ ! -f $REF$ext ]]; then err "reference index missing: $REF$ext"; fi
            done
            dict=${REF%.*}.dict
            if [[ ! -f $dict ]]; then err "sequence dictionary missing: $dict"; fi
        fi
        for tool in fastqc fastp bwa samtools gatk multiqc; do
            if ! command -v "$tool" >/dev/null 2>&1; then err "tool not on PATH: $tool"; fi
        done
    fi

    if (( ${#ERRORS[@]} > 0 )); then
        log "stage 0: found ${#ERRORS[@]} problem(s):"
        for ((i = 0; i < ${#ERRORS[@]}; i++)); do printf '  - %s\n' "${ERRORS[i]}" >&2; done
        exit 1
    fi
    log "stage 0: $n sample(s) passed validation"
}

# ---------------------------------------------------------------- stage 1
stage_qc_raw() {
    local d=$OUT/01_qc_raw i
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        log "qc_raw: '${IDS[i]}'"
        fastqc -q -t "$THREADS" -o "$d" "${R1S[i]}" ${R2S[i]:+"${R2S[i]}"} >&2
    done
    if ! ls "$d"/*_fastqc.zip >/dev/null 2>&1; then die "qc_raw: no FastQC output in $d"; fi
}

# ---------------------------------------------------------------- stage 2
stage_trim() {
    local d=$OUT/02_trim i id base
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        id=${IDS[i]}; base=$d/$id
        log "trim: '$id' (${LIBS[i]})"
        if [[ ${LIBS[i]} == paired ]]; then
            fastp -i "${R1S[i]}" -I "${R2S[i]}" \
                  -o "$base.trim_R1.fastq.gz" -O "$base.trim_R2.fastq.gz" \
                  --detect_adapter_for_pe -w "$THREADS" \
                  -j "$base.fastp.json" -h "$base.fastp.html" >&2 2>"$base.fastp.log"
            need_file "$base.trim_R2.fastq.gz" "trim '$id'"
        else
            fastp -i "${R1S[i]}" -o "$base.trim_R1.fastq.gz" -w "$THREADS" \
                  -j "$base.fastp.json" -h "$base.fastp.html" >&2 2>"$base.fastp.log"
        fi
        need_file "$base.trim_R1.fastq.gz" "trim '$id'"
        need_file "$base.fastp.json" "trim '$id'"
    done
}

# ---------------------------------------------------------------- stage 3
stage_align() {
    local d=$OUT/03_align t=$OUT/02_trim i id r1 r2 bam n
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        id=${IDS[i]}; bam=$d/$id.sorted.bam
        r1=$t/$id.trim_R1.fastq.gz; r2=""
        if [[ ${LIBS[i]} == paired ]]; then r2=$t/$id.trim_R2.fastq.gz; fi
        log "align: '$id'"
        bwa mem -t "$THREADS" -R "@RG\tID:${id}\tSM:${id}" "$REF" "$r1" ${r2:+"$r2"} 2>"$d/$id.bwa.log" \
            | samtools sort -@ 2 -T "$d/$id.sorttmp" -o "$bam" -
        if ! samtools quickcheck "$bam"; then die "align '$id': $bam failed samtools quickcheck"; fi
        n=$(samtools view -c -F 4 "$bam")
        if (( n == 0 )); then die "align '$id': no mapped reads in $bam (see $d/$id.bwa.log)"; fi
        log "align: '$id' $n mapped reads"
    done
}

# ---------------------------------------------------------------- stage 4
stage_postprocess() {
    local d=$OUT/04_postprocess a=$OUT/03_align i id out
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        id=${IDS[i]}; out=$d/$id.dedup.bam
        log "postprocess: '$id'"
        gatk_ MarkDuplicates -I "$a/$id.sorted.bam" -O "$out" -M "$d/$id.dup_metrics.txt"
        samtools index "$out"
        samtools flagstat "$out" > "$d/$id.flagstat.txt"
        if ! samtools quickcheck "$out"; then die "postprocess '$id': $out failed quickcheck"; fi
        need_file "$out.bai" "postprocess '$id'"
    done
}

# ---------------------------------------------------------------- stage 5
stage_quantify() {
    local d=$OUT/05_quantify p=$OUT/04_postprocess i id
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        id=${IDS[i]}
        log "quantify: '$id' HaplotypeCaller -ERC GVCF -L $REGION"
        gatk_ HaplotypeCaller -R "$REF" -I "$p/$id.dedup.bam" -O "$d/$id.g.vcf.gz" \
              -ERC GVCF -L "$REGION"
        need_file "$d/$id.g.vcf.gz" "quantify '$id'"
    done
}

# ---------------------------------------------------------------- stage 6
stage_merge() {
    local d=$OUT/06_merge g=$OUT/05_quantify i
    local -a vargs=()
    mkdir -p "$d"
    for ((i = 0; i < ${#IDS[@]}; i++)); do vargs+=(-V "$g/${IDS[i]}.g.vcf.gz"); done
    log "merge: CombineGVCFs over ${#IDS[@]} sample(s)"
    gatk_ CombineGVCFs -R "$REF" -L "$REGION" "${vargs[@]}" -O "$d/cohort.g.vcf.gz"
    log "merge: GenotypeGVCFs"
    gatk_ GenotypeGVCFs -R "$REF" -L "$REGION" -V "$d/cohort.g.vcf.gz" -O "$d/cohort.vcf.gz"
    need_file "$d/cohort.vcf.gz" merge
    log "merge: $(count_records "$d/cohort.vcf.gz") joint-genotyped records"
}

# ---------------------------------------------------------------- stage 7
stage_analyze() {
    local d=$OUT/07_analyze in=$OUT/06_merge/cohort.vcf.gz out total pass
    out=$d/cohort.filtered.vcf.gz
    mkdir -p "$d"

    gatk_ SelectVariants -R "$REF" -V "$in" --select-type-to-include SNP -O "$d/snps.vcf.gz"
    gatk_ SelectVariants -R "$REF" -V "$in" --select-type-to-include INDEL \
          --select-type-to-include MIXED -O "$d/indels.vcf.gz"

    # GATK Best Practices hard filters. VariantFiltration tags FILTER; it removes nothing.
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

# ---------------------------------------------------------------- stage 8
stage_qc_report() {
    local d=$OUT/08_qc_report
    mkdir -p "$d"
    multiqc -f -o "$d" "$OUT/01_qc_raw" "$OUT/02_trim" "$OUT/04_postprocess" >&2
    need_file "$d/multiqc_report.html" qc_report
}

# ---------------------------------------------------------------- stage 9
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

# ---------------------------------------------------------------- main
mkdir -p "$OUTARG"
OUT=$(cd "$OUTARG" && pwd)
log "run_pipeline: sheet=$SHEET outdir=$OUT last=$LAST REF=$REF REGION=$REGION"
for ((s = 0; s <= LAST_IDX; s++)); do
    log "=== stage $s: ${STAGES[s]} ==="
    "stage_${STAGES[s]}"
done
log "run_pipeline: finished through stage '$LAST'"
