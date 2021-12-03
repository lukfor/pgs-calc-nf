# pgs-calc-nf

> Nextflow pipeline to calculate polygenetic riskscores using pgs-calc

## Requirements

- Nextflow:

```
curl -s https://get.nextflow.io | bash
```

- Docker

## Installation

Build docker image before run the pipeline:

```
docker build -t lukfor/pgs-calc-nf . # don't ingore the dot here
```


Test the pipeline and the created docker image with test-data:

```
nextflow run main.nf --project my-project-name --input test-data/*.dose.vcf.gz --output output --pgs_scores PGS000013,PGS000014
```
