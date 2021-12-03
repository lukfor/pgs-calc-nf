imputed_vcf_files_ch = Channel.fromPath(params.input)

process calcScores {

  publishDir params.output, mode: 'copy'

  input:
    file imputed_vcf_files from imputed_vcf_files_ch.collect()

  output:
    file "${params.project}.scores.txt" into results_ch
    file "${params.project}.scores.html" into report_ch

  """
  # Download latest meta data
  wget https://www.pgscatalog.org/rest/score/all -O pgs-catalog.json

  pgs-calc ${imputed_vcf_files} \
    --ref ${params.pgs_scores} \
    --out ${params.project}.scores.txt \
    --report-html ${params.project}.scores.html \
    --meta pgs-catalog.json \
    --no-ansi
  """

}


workflow.onComplete {
    println "Pipeline completed at: $workflow.complete"
    println "Execution status: ${ workflow.success ? 'OK' : 'failed' }"
}
