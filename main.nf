
Channel.fromFilePairs(params.dbsnp_index).set { dbsnp_index_ch}
vcf_files = Channel.fromPath(params.genotypes_imputed)

if (params.genotypes_imputed_format != 'vcf'){
  exit 1, "PGS Calc supports only vcf files."
}

if (params.genotypes_build == "hg19"){
  dbsnp_build = "GRCh37p13";
  build_filter = "hg19|GRCh37|NR"
} else if (params.genotypes_build == "hg38"){
  dbsnp_build = "GRCh38p7";
  build_filter = "hg38|GRCh38|NR"
} else {
  exit 1, "Unsupported build."
}


ExcelToCsvJava = file("$baseDir/src/ExcelToCsv.java")
ConvertScoreJava = file("$baseDir/src/ConvertScore.java")


process cacheJBangScripts {

  input:
    file ExcelToCsvJava
    file ConvertScoreJava

  output:
    file "ExcelToCsv.jar" into ExcelToCsv
    file "ConvertScore.jar" into ConvertScore

  """
  jbang export portable -O=ExcelToCsv.jar ${ExcelToCsvJava}
  jbang export portable -O=ConvertScore.jar ${ConvertScoreJava}
  """

}


if (params.pgs_catalog_url.startsWith('https://') || params.pgs_catalog_url.startsWith('http://')){

  process downloadPGSCatalogMeta {

    output:
      file "*.xlsx" into pgs_catalog_excel_file

    """
    wget ${params.pgs_catalog_url}
    """

  }

} else {

  pgs_catalog_excel_file = file(params.pgs_catalog_url)

}


process convertPgsCatalogMeta {

  input:
    file ExcelToCsv
    file excel_file from pgs_catalog_excel_file

  output:
    file "*.csv" into pgs_catalog_csv_file

  """
  java -jar ${ExcelToCsv} \
    --input ${excel_file} \
    --sheet Scores \
    --output pgs_all_metadata.csv
  """

}


// filter out other pgs scores
pgs_catalog_csv_file
  .splitCsv(header: true, sep: ',', quote:'"')
  .filter(row -> row['Polygenic Score (PGS) ID'] in (params.pgs_scores.split(',')) )
  .set { scores_ch }

process calcScores {

  publishDir params.output, mode: 'copy'

  input:
    file(vcf_file) from vcf_files.collect()
    val score from scores_ch
    tuple val(dbsnp_index), file(dbsnp_index_file) from dbsnp_index_ch.collect()
    file ConvertScore

  output:
    file "*.txt" into results_ch
    file "*.html" into report_ch
    file "*.txt.gz" optional true into pgs_catalog_scores_files
    file "*.log" into pgs_catalog_scores_logs

  script:
    score_id = score['Polygenic Score (PGS) ID']
    score_ftp_link = score['FTP link']


  """

  ##TODO check build and write to log if not same.

  wget ${score_ftp_link} -O ${score_id}.original.txt.gz
  java -jar ${ConvertScore} \
    --input ${score_id}.original.txt.gz \
    --output ${score_id}.txt.gz \
    --dbsnp ${dbsnp_index}.txt.gz
  rm ${score_id}.original.txt.gz

  wget https://www.pgscatalog.org/rest/score/all -O pgs-catalog.json

  pgs-calc *.vcf.gz \
    --ref ${score_id} \
    --out ${score_id}.txt \
    --report-html ${score_id}.html \
    --meta pgs-catalog.json \
    --no-ansi
  """

}

workflow.onComplete {
    println "Pipeline completed at: $workflow.complete"
    println "Execution status: ${ workflow.success ? 'OK' : 'failed' }"
}
