#!/usr/bin/env bash
#=============================================================================
# validate_samplesheet.sh — stage 0: check the samplesheet, every FASTQ and the
# reference before anything computes, and report every problem together.
#
#   validate_samplesheet.sh <samplesheet.csv> <reference.fa> [<reference.dict>]
#
# Weeks 1-3's stage 0, in bin/ so a rule can run it by its path. Snakemake links
# nothing into a job's folder, so each FASTQ is opened at the path the samplesheet
# gives: absolute, or relative to the samplesheet's own folder.
# Columns are found by name in the header. Messages go to stderr; stdout stays empty.
#=============================================================================
set -euo pipefail

SHEET=${1:?usage: validate_samplesheet.sh <samplesheet.csv> <reference.fa> [<reference.dict>]}
REF=${2:?usage: validate_samplesheet.sh <samplesheet.csv> <reference.fa> [<reference.dict>]}
DICT=${3:-${REF%.*}.dict}                 # smoke.dict, not smoke.fa.dict
SHEET_DIR=$(dirname "$SHEET")
at_sheet() { case $1 in ""|/*) printf '%s' "$1" ;; *) printf '%s/%s' "$SHEET_DIR" "$1" ;; esac; }

log() { printf '[validate] %s\n' "$*" >&2; }
problems=()
err() { problems+=("$*"); }

check_fastq() {   # <sample_id> <R1|R2> <file name> -> 0 if it is a complete gzip
    local id=$1 label=$2 f=$3
    if [[ ! -e $f ]]; then err "sample '$id': $label file not found: $f"; return 1; fi
    if [[ ! -s $f ]]; then err "sample '$id': $label file is empty: $f"; return 1; fi
    if ! gzip -t "$f" 2>/dev/null; then
        err "sample '$id': $label is not a complete gzip stream (truncated or corrupt): $f"; return 1
    fi
}

seen=" "
n=0
while IFS=$'\x1f' read -r id lt r1 r2; do   # \x1f: not whitespace, so empty fields survive
    n=$(( n + 1 ))
    if [[ -z $id ]]; then err "row $(( n + 1 )): empty sample_id"; continue; fi
    case " $seen " in *" $id "*) err "sample '$id': duplicate sample_id" ;; esac
    seen="$seen$id "
    log "checking sample '$id' ($lt)"

    r1=$(at_sheet "$r1")
    r2=$(at_sheet "$r2")

    case $lt in
        paired) [[ -n $r2 ]] || err "sample '$id': library_type is paired but r2_fastq is empty" ;;
        single) ;;
        *)      err "sample '$id': unrecognised library_type '$lt' (expected paired or single)" ;;
    esac

    if [[ -z $r1 ]]; then err "sample '$id': r1_fastq is empty"; continue; fi
    ok1=0; ok2=0
    if check_fastq "$id" R1 "$r1"; then ok1=1; fi
    if [[ $lt == paired && -n $r2 ]] && check_fastq "$id" R2 "$r2"; then ok2=1; fi

    # Assert on the data, not just on exit codes.
    if (( ok1 )); then
        c1=$(gzip -dc "$r1" | wc -l | tr -d ' ')
        if (( c1 == 0 )); then err "sample '$id': R1 contains no reads: $r1"
        elif (( c1 % 4 != 0 )); then err "sample '$id': R1 has $c1 lines, not a multiple of 4: $r1"; fi
        if (( ok2 )); then
            c2=$(gzip -dc "$r2" | wc -l | tr -d ' ')
            (( c1 == c2 )) || err "sample '$id': R1 has $(( c1 / 4 )) reads but R2 has $(( c2 / 4 ))"
        fi
    fi
done < <(awk -F, -v OFS=$'\x1f' '
    NR == 1 { for (i = 1; i <= NF; i++) { gsub(/\r/, "", $i); col[$i] = i }
              if (!("sample_id" in col && "library_type" in col && "r1_fastq" in col && "r2_fastq" in col)) {
                  print "samplesheet header lacks sample_id, library_type, r1_fastq or r2_fastq" > "/dev/stderr"; exit 65 }
              next }
    /^[[:space:],]*$/ { next }
    { gsub(/\r/, ""); print $col["sample_id"], $col["library_type"], $col["r1_fastq"], $col["r2_fastq"] }' "$SHEET")

(( n > 0 )) || err "samplesheet has no sample rows: $SHEET"

[[ -s $REF ]]      || err "reference not found: $REF"
[[ -s $REF.fai ]]  || err "reference index missing: $REF.fai"
[[ -s $REF.bwt ]]  || err "BWA index missing: $REF.bwt"
[[ -s $DICT ]]     || err "sequence dictionary missing: $DICT"

if (( ${#problems[@]} > 0 )); then
    log "found ${#problems[@]} problem(s):"
    for p in "${problems[@]}"; do printf '  - %s\n' "$p" >&2; done
    exit 65
fi
log "validation passed: $n sample(s)"
