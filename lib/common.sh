#!/usr/bin/env bash
# lib/common.sh — what every stage needs. Sourced by run_pipeline.sh and run_sample.sh.
#
# Settings, logging, the stage list, and reading the samplesheet by column name.
# Only REF and REGION differ between the laptop smoke run and the Explorer run;
# a Slurm job starts with nothing in front of bash, so it gets the Explorer values.
set -euo pipefail

REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}
THREADS=${THREADS:-4}          # a job script sets this from SLURM_CPUS_PER_TASK
JAVA_MEM=${JAVA_MEM:-4g}
TMP_ROOT=${TMPDIR:-/tmp}       # a job script points TMPDIR at /tmp/$SLURM_JOB_ID

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)
LAST_PER_SAMPLE=quantify       # stages after this one need every sample at once

# ---------------------------------------------------------------- helpers
# Everything human-readable goes to stderr; stdout stays empty.
log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }
need_file() { if [[ ! -s $1 ]]; then die "$2: expected output missing or empty: $1"; fi; }
# java.io.tmpdir is honoured by both GATK and Picard tools (Picard has no --tmp-dir).
gatk_() { gatk --java-options "-Xmx${JAVA_MEM} -Djava.io.tmpdir=${TMP_ROOT}" "$@" >&2; }
lc()   { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
trim() { local s=$1; s=${s#"${s%%[![:space:]]*}"}; s=${s%"${s##*[![:space:]]}"}; printf '%s' "$s"; }
count_records() { gzip -dc "$1" | awk '!/^#/ {n++} END {print n+0}'; }

stage_index() {   # stage_index <name> -> prints its index, or -1
    local s
    for ((s = 0; s < ${#STAGES[@]}; s++)); do
        if [[ ${STAGES[s]} == "$1" ]]; then printf '%s' "$s"; return 0; fi
    done
    printf '%s' -1
}

setup_out() {     # setup_out <outdir> -> sets OUT to its absolute path
    mkdir -p "$1"
    OUT=$(cd "$1" && pwd)
}

run_stages() {    # run_stages <first_idx> <last_idx>; stage 0 always runs first
    local first=$1 last=$2 s
    log "=== stage 0: validate ==="
    stage_validate
    for ((s = (first > 1 ? first : 1); s <= last; s++)); do
        log "=== stage $s: ${STAGES[s]} ==="
        "stage_${STAGES[s]}"
    done
}

# ---------------------------------------------------------------- samplesheet
# Parallel arrays, one entry per row, filled by load_sheet. Columns are found by
# name in the header, so extra columns (the Explorer sheet has ten) are ignored.
IDS=(); R1S=(); R2S=(); LIBS=(); CONDS=()
ERRORS=()
ONLY_SAMPLE=${ONLY_SAMPLE:-}   # set by run_sample.sh: restrict the run to one sample_id
err() { ERRORS+=("$*"); }

# A relative FASTQ path is taken relative to the current directory; failing
# that, relative to the samplesheet's folder.
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
        if (( rowno == 1 )); then continue; fi                 # header
        line=${line%$'\r'}                                     # tolerate CRLF
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

# Keep only the row for ONLY_SAMPLE (called by stage 0 once the sheet has passed).
subset_to_sample() {
    local i
    local -a ids=() r1s=() r2s=() libs=() conds=()
    for ((i = 0; i < ${#IDS[@]}; i++)); do
        if [[ ${IDS[i]} == "$ONLY_SAMPLE" ]]; then
            ids+=("${IDS[i]}"); r1s+=("${R1S[i]}"); r2s+=("${R2S[i]}")
            libs+=("${LIBS[i]}"); conds+=("${CONDS[i]}")
        fi
    done
    IDS=("${ids[@]}"); R1S=("${r1s[@]}"); R2S=("${r2s[@]}"); LIBS=("${libs[@]}"); CONDS=("${conds[@]}")
}
