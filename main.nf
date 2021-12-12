
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


process cacheJBangScripts {

  input:
    file ExcelToCsvJava

  output:
    file "ExcelToCsv.jar" into ExcelToCsv

  """
  jbang export portable -O=ExcelToCsv.jar ${ExcelToCsvJava}
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

  output:
    file "*.txt" into score_chunks_ch
    file "*.json" into report_chunks_ch
    file "*.html"
    file "*.txt.gz"
    file "*.log"

  script:
    score_id = score['Polygenic Score (PGS) ID']
    score_ftp_link = score['FTP link']


  """

  set -e

  ##TODO check build and write to log if not same.

  wget ${score_ftp_link} -O ${score_id}.original.txt.gz

  pgs-calc resolve \
    --in ${score_id}.original.txt.gz \
    --out ${score_id}.txt.gz \
    --dbsnp ${dbsnp_index}.txt.gz > ${score_id}.log

  rm ${score_id}.original.txt.gz

  wget https://www.pgscatalog.org/rest/score/all -O pgs-catalog.json

  pgs-calc apply *.vcf \
    --ref ${score_id}.txt.gz \
    --out ${score_id}.txt \
    --report-html ${score_id}.html \
    --report-json ${score_id}.json \
    --meta pgs-catalog.json \
    --no-ansi
  """

}

workflow.onComplete {
    println "Pipeline completed at: $workflow.complete"
    println "Execution status: ${ workflow.success ? 'OK' : 'failed' }"
}
