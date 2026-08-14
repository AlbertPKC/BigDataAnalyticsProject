# IST3134 Group Assignment — Big Data Analytics in the Cloud

**Team:** <name 1>, <name 2>
**Module:** IST3134 – Big Data Analytics in the Cloud, May Semester 2026

## Problem

<One paragraph: benchmarking query/write performance and cost across local SQL,
MapReduce, Spark, managed cloud clusters, and lakehouse/serverless SQL engines,
using a large flight-pricing dataset. Expand once results are in.>

## Dataset

Source: [Flight Prices — Kaggle](https://www.kaggle.com/datasets/dilwong/flightprices)
Each row is a purchasable Expedia ticket, 2022-04-16 to 2022-10-05, across 16 US airports (~30GB, ~82M rows).

This project uses a deterministic ~15GB interlaced sample (every 2nd data row of the
original file, header preserved) for reproducibility across every tier. To regenerate it:

```bash
awk 'NR==1 || (NR%2==0)' itineraries.csv > itineraries_sample.csv
md5sum itineraries_sample.csv
```

**Canonical sample checksum:** `<paste md5sum output here once generated>`

The sample itself is **not** committed to this repo (see `.gitignore`) — it lives at:
`s3://<your-bucket-name>/canonical/itineraries_sample.csv`
(S3 access is scoped to the AWS Academy Learner Lab session used for this project;
contact the team for a copy if the bucket is no longer accessible after the course ends.)

## Repo structure

```
/data-prep/            sampling scripts, checksums, S3 upload scripts
/tier0-mysql-vanilla/
/tier1-mysql-indexed/
/tier2-duckdb-postgres/
/tier3-hadoop-mapreduce/
/tier4-spark-yarn/
/tier5-emr-single-small/
/tier6-emr-single-large/
/tier7-emr-multinode/
/tier8-spark-sql/
/tier9-lakehouse-iceberg/
/tier10-athena/
/tier11-hive-stretch/
/tier12-bigquery-stretch/
/hardware-comparison/  stretch task: local SQL across two laptops (storage + memory bandwidth)
/results/               exported timings/screenshots per tier
/report/                final report (Word/PDF) and any supporting figures
```

## How to reproduce

Full step-by-step setup, install commands, and sanity checks for every tier are in
`IST3134_Project_Instructions.md`. The hardware stretch task has its own walkthrough in
`Stretch_Hardware_Comparison_Instructions.md`. Raw timings and cost estimates are logged
in `results_tracking_template.xlsx`.

## Fixed benchmark queries

The same six queries are run across every tier for a fair comparison — see
`IST3134_Project_Instructions.md` §1.8 for the full definitions (single-row lookup,
range query, aggregation, join/enrichment, single write, range write/update).

## Results

<Link to or embed a summary of `results_tracking_template.xlsx` once populated.>

## Individual reflections

<name 1>: <reflection>
<name 2>: <reflection>
