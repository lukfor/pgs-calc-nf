
if (params.genotypes_imputed_have_index) {
  Channel.fromFilePairs(params.genotypes_imputed, checkIfExists:true).map{it[1][0]}.set{vcf_files}
  Channel.fromFilePairs(params.genotypes_imputed, checkIfExists:true).map{it[1][0]}.set{vcf_files2}
} else {
  Channel.fromPath(params.genotypes_imputed, checkIfExists:true).set{vcf_files}
  Channel.fromPath(params.genotypes_imputed, checkIfExists:true).set{vcf_files2}
}

Channel.fromPath(params.scores, checkIfExists:true).set{prepared_scores_ch}

scores_meta_file = file(params.scores_meta)


if (params.chunk_size != 0) {

  process CREATE_CHUNKS {

    input:
      file vcfs from vcf_files.collect()

    output:
      file "chunks.txt" into chunks_file

    """
    pgs-calc create-chunks ${vcfs} \
      --size ${params.chunk_size} \
      --out chunks.txt
    """

  }

  vcf_files2.map{tuple(it.name, it)}.set{vcf_files_index}

  chunks_file
    .splitCsv(header: true, sep: ',', quote:'"')
    .map(row -> tuple(row['FILENAME'], row['START'], row['END']))
    .combine(vcf_files_index, by: 0).set{chunks_ch}

} else {
  vcf_files.map{tuple(it.name, 1, 250000000, it)}.set{chunks_ch}
}


process CALCULATE_CHUNKS {

  input:
    tuple val(name), val(start), val(end), file(vcf_file) from chunks_ch
    file scores from prepared_scores_ch.collect()

  output:
    file "*.txt" optional true into score_chunks_ch
    file "*.info" optional true into report_chunks_ch
    file "*.variants" optional true into variants_chunks_ch
    file "*.log"

  script:
    name = "${vcf_file.baseName}_${start}_${end}"

  """

  pgs-calc apply ${vcf_file} \
    --ref ${scores.join(',')} \
    --genotypes ${params.genotypes_imputed_dosages} \
    --out ${name}.scores.txt \
    --info ${name}.scores.info \
    --start ${start} \
    --end ${end} \
    ${params.write_variants ? "--write-variants ${name}.variants " : ""} \
    ${params.fix_strand_flips ? "--fix-strand-flips" : ""} \
    --min-r2 ${params.min_r2} \
    --no-ansi > ${name}.scores.log

  """

}

process MERGE_CHUNKS_SCORES {

  publishDir params.output, mode: 'copy'

  input:
    file(score_chunks) from score_chunks_ch.collect()

  output:
    file "*.txt" into merged_score_files

  """

  pgs-calc merge-score ${score_chunks} \
    --out ${params.project}.scores.txt

  """

}

process MERGE_CHUNKS_INFOS {

  publishDir params.output, mode: 'copy'

  input:
    file(report_chunks) from report_chunks_ch.collect()

  output:
    file "*.info" into merged_info_files

  """

  pgs-calc merge-info ${report_chunks} \
    --out ${params.project}.info

  """

}

process MERGE_CHUNKS_VARIANTS {

  publishDir params.output, mode: 'copy'

  input:
    file(variants_chunks) from variants_chunks_ch.collect()

  output:
    file "*.variants" into merged_variants_files

  """

  pgs-calc merge-variants ${variants_chunks} \
    --out ${params.project}.variants

  """

}

process CREATE_HTML_REPORT {

  publishDir params.output, mode: 'copy'

  input:
    file(merged_score) from merged_score_files
    file(merged_info) from merged_info_files
    file(scores_meta) from scores_meta_file


  output:
    file "*.html"
    file "*.coverage.txt"

  script:
      def meta_param = scores_meta.name != 'NO_FILE' ? "--meta ${scores_meta}" : ''

  """

  pgs-calc report \
    --data ${merged_score} \
    --info ${merged_info} \
    ${meta_param} \
    --out ${params.project}.scores.html

  pgs-calc report \
    --data ${merged_score} \
    --info ${merged_info} \
    ${meta_param} \
    --template txt \
    --out ${params.project}.scores.coverage.txt

  """

}


workflow.onComplete {
    println "Pipeline completed at: $workflow.complete"
    println "Execution status: ${ workflow.success ? 'OK' : 'failed' }"
}
