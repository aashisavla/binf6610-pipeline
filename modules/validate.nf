// Stage 0 · validate — the samplesheet, every FASTQ and the reference, before any compute.
// Every FASTQ is an input, so Nextflow links each one into this task's folder, and the
// check opens the same files the later stages will, by file name.
process VALIDATE {
    container params.containers.tools

    input:
    path samplesheet
    path fastqs
    path ref
    path ref_index
    path ref_dict

    output:
    path samplesheet, emit: sheet

    script:
    """
    validate_samplesheet.sh ${samplesheet} ${ref} ${ref_dict}
    """
}
