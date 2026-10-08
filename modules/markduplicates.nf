// Stage 4 · postprocess — mark duplicates, index, and alignment statistics for MultiQC.
process MARKDUPLICATES {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("${meta.id}.dedup.bam"), path("${meta.id}.dedup.bam.bai"), emit: bam
    path "${meta.id}.dup_metrics.txt",                                               emit: metrics
    path "${meta.id}.flagstat.txt",                                                  emit: flagstat

    script:
    def xmx = Math.max((task.memory.toGiga() * 0.8) as int, 1)
    """
    gatk --java-options "-Xmx${xmx}g -Djava.io.tmpdir=." MarkDuplicates \\
        -I ${bam} -O ${meta.id}.dedup.bam -M ${meta.id}.dup_metrics.txt
    samtools index ${meta.id}.dedup.bam
    samtools flagstat ${meta.id}.dedup.bam > ${meta.id}.flagstat.txt
    """
}
