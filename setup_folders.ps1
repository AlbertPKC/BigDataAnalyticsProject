# Run this from inside your cloned repo folder (where .gitignore and README.md live).
# Creates every tier folder in one shot, plus a .gitkeep in each so Git actually
# tracks the empty folders (Git doesn't track empty directories on their own).

$folders = @(
    "00.0-mysql-vanilla",
    "01.0-mysql-indexed",
    "02.0-duckdb-postgres",
    "03.0-hadoop-mapreduce",
    "04.0-spark-yarn",
    "05.0-emr-single-small",
    "06.0-emr-single-large",
    "07.0-emr-multinode",
    "08.0-spark-sql",
    "09.0-lakehouse-iceberg",
    "10.0-athena",
    "11.0-hive-stretch",
    "12.0-bigquery-stretch",
    "data-prep",
    "hardware-comparison",
    "results",
    "report"
)

foreach ($folder in $folders) {
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    New-Item -ItemType File -Force -Path "$folder\.gitkeep" | Out-Null
}

Write-Host "Created $($folders.Count) folders with .gitkeep placeholders."
