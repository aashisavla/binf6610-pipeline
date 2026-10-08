// Stage 3 · align — BWA-MEM to the reference, straight into a sorted BAM.
// The read group's SM is the sample_id, so GATK names the sample's VCF column after it.
process BWA_MEM {
    tag "${meta.id}"
    container params.containers.bwa

    input:
    tuple val(meta), path(reads)
    path ref
    path ref_index

    output:
    tuple val(meta), path("${meta.id}.sorted.bam"), emit: bam

    script:
    """
    bwa mem -t ${task.cpus} -R "@RG\\tID:${meta.id}\\tSM:${meta.id}" ${ref} ${reads} \\
        2> ${meta.id}.bwa.log \\
        | samtools sort -@ ${task.cpus} -T ./${meta.id}.sort -o ${meta.id}.sorted.bam -
    samtools quickcheck ${meta.id}.sorted.bam

    # Assert on the data, not just the exit code: an empty BAM is a failure.
    mapped=\$(samtools view -c -F 4 ${meta.id}.sorted.bam)
    (( mapped > 0 )) || { echo "${meta.id}: no mapped reads (see ${meta.id}.bwa.log)" >&2; exit 1; }
    """
}
