// Stage 5 · quantify — per-sample HaplotypeCaller in GVCF mode, restricted to the region.
// Its two outputs are plain paths: they go only, through collect(), to stage 6.
process HAPLOTYPECALLER {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam), path(bai)
    path ref
    path ref_index
    path ref_dict
    val  region

    output:
    path "${meta.id}.g.vcf.gz",     emit: gvcf
    path "${meta.id}.g.vcf.gz.tbi", emit: tbi

    script:
    def xmx = Math.max((task.memory.toGiga() * 0.8) as int, 1)
    """
    gatk --java-options "-Xmx${xmx}g -Djava.io.tmpdir=." HaplotypeCaller \\
        -R ${ref} -I ${bam} -O ${meta.id}.g.vcf.gz \\
        -ERC GVCF -L ${region} --native-pair-hmm-threads ${task.cpus}
    """
}
