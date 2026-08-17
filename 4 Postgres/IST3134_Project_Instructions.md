# IST3134 Group Project — Execution Lab Manual (renumbered to match your workbook)
## Flight Prices Benchmark: MySQL → DuckDB → Postgres → Hadoop → Spark → EMR → Lakehouse → Serverless SQL

> **This is a renumbered copy of the original lab manual**, adjusted to match the tier numbers already in your `results_tracking_template.xlsx` **Tier Reference** tab (DuckDB and Postgres split into their own tiers, ahead of the distributed-computing tiers). All step-by-step content, sanity checks, and commands are unchanged from the original — only tier numbers, folder names, and cross-references between tiers have been updated. Log everything into `results_tracking_template.xlsx` as you go.

**Golden rule for the whole project:** every tier must run against the *exact same slice of data* and the *exact same six queries*. Section 1 below builds that slice once, deterministically, and every later tier just points at it. Don't re-derive the sample per tier.

**Your tier map (workbook Tier Reference tab):**

| tier | tier_name | purpose |
|---|---|---|
| 0 | Data Preparation | One-time cost of building the canonical dataset |
| 1 | MySQL vanilla (no index) | Baseline — reproduces the original slow experience |
| 2 | MySQL indexed (+partitioned) | Isolates the effect of indexing/partitioning alone |
| 3 | DuckDB | Modern embedded columnar engine |
| 4 | Postgres | Modern indexed row store |
| 5 | Self-managed Hadoop MapReduce | Historical distributed batch baseline |
| 6 | Self-managed Spark on YARN | Spark vs MapReduce, same hardware |
| 7 | EMR single small node | Managed service overhead vs self-managed |
| 8 | EMR single large node | Vertical scaling test |
| 9 | EMR multi-node cluster | Horizontal scaling test, resource-matched to Tier 8 |
| 10 | Spark SQL / DataFrames (joins, windows) | Explicit query-layer explanation artifact |
| 11 | Lakehouse: S3 + Glue + Iceberg | ACID single-write / range-write demonstration |
| 12 | Athena: CSV vs Parquet vs Iceberg | Cost-aware serverless SQL, format comparison |
| 13 | Hive vs Spark SQL on EMR (stretch) | Isolates query engine, same cluster/data |
| 14 | BigQuery Sandbox (stretch) | Cross-cloud serverless SQL comparison |

---

## 0. One-time setup

### 0.1 — Repo structure
Create a GitHub repo (private during dev is fine; must be public or link-shared by submission). Create this folder structure now:
```
/data-prep/                    # tier 0
/tier1-mysql-vanilla/
/tier2-mysql-indexed/
/tier3-duckdb/
/tier4-postgres/
/tier5-hadoop-mapreduce/
/tier6-spark-yarn/
/tier7-emr-single-small/
/tier8-emr-single-large/
/tier9-emr-multinode/
/tier10-spark-sql/
/tier11-lakehouse-iceberg/
/tier12-athena/
/tier13-hive-stretch/
/tier14-bigquery-stretch/
/results/                      # screenshots + exported CSVs of timings, one per tier
```

### 0.2 — Access checklist (tick before Section 1)
- [ ] Kaggle account + API token (`kaggle.json`) ready
- [ ] AWS Academy Learner Lab access confirmed — Start Lab works, you can see remaining credit on the lab page
- [ ] Docker installed locally (`docker --version` works)
- [ ] MySQL installed locally (not Docker — you specifically want to reproduce your own prior experience)
- [ ] Python 3.10+ available (`python3 --version`), with `pip install duckdb pandas mysql-connector-python psycopg2-binary pyspark boto3` working
- [ ] AWS CLI installed and configured (`aws --version`, `aws configure` using the Academy Lab's temporary credentials from the "AWS Details" panel)

### 0.3 — Results tracking
Open `results_tracking_template.xlsx`. Skim the **Legend** tab now so you know what to fill in as you complete each tier below.

---

## 1. Build the canonical ~15GB dataset (do this exactly once)

**Why an interlaced sample instead of a straight cut:** taking the first N rows of the file would bias your sample toward whatever date range or airport happens to be sorted first in the source CSV. Keeping every 2nd row preserves the full date range, all 16 airports, and the overall distribution of fares — you're thinning the data, not truncating it. It's also deterministic: run the same command on the same source file and you get a byte-identical result every time.

**Time every step below and log it.** Downloading ~30GB, scanning it with `awk`, hashing it, and pushing ~15GB to S3 are each genuinely heavy I/O/compute operations. Log these into the **Benchmark Log** tab as `tier = 0` (Data Preparation). Wrap each command with the `time` builtin:
```bash
time <your command here>
```
The `real` line in `time`'s output (not `user` or `sys`) is what belongs in the `wall_clock_seconds` column.

### 1.1 — Download the full source file (once, on EC2 — not your laptop)
1. Start your AWS Academy Learner Lab, launch a small EC2 instance (t2.micro/t3.medium is enough — you're not processing yet, just downloading and streaming).
2. SSH in (or use EC2 Instance Connect), then:
   ```bash
   pip install kaggle --user
   mkdir -p ~/.kaggle && mv kaggle.json ~/.kaggle/ && chmod 600 ~/.kaggle/kaggle.json
   time kaggle datasets download -d dilwong/flightprices -p ~/data --unzip
   ```
3. **Sanity check — expected output:**
   ```bash
   ls -lh ~/data/itineraries.csv        # should show ~30-31 GB
   wc -l ~/data/itineraries.csv         # should be in the tens of millions (record the exact number)
   head -3 ~/data/itineraries.csv       # first line = header row; next two = real records
   ```
   If the file size is a few hundred MB instead of ~30GB, the Kaggle download was interrupted — delete and re-run.

   **Log it:** `tier = 0`, `engine = kaggle-cli`, `query_id = DOWNLOAD`, `query_type = data-prep`, `wall_clock_seconds` = the `real` time, `node_spec` = your EC2 instance type, `notes` = your internet/EC2 network throughput context.

### 1.2 — Create the interlaced 50% sample
```bash
cd ~/data
time awk 'NR==1 || (NR%2==0)' itineraries.csv > itineraries_sample.csv
```
`NR` is the line number. `NR==1` always keeps the header. For every other line, `NR%2==0` keeps only even-numbered lines — since the header occupies line 1 (odd), the first data row is line 2 (even, kept), the second data row is line 3 (odd, dropped), and so on. Exactly every other data row, in original order, no randomness.

**Sanity check:**
```bash
ls -lh itineraries_sample.csv                 # roughly half the original size, ~15 GB
wc -l itineraries_sample.csv                  # ~ (original_data_rows / 2) + 1 header row
```
If the row count isn't close to half, check for stray blank lines or unescaped newlines inside quoted fields (`grep -c '""'` sanity pass if numbers look off).

**Log it:** `tier = 0`, `engine = awk`, `query_id = SAMPLE`, `query_type = data-prep`, `dataset_rows` = the original full row count, `wall_clock_seconds` = the `real` time. Good comparison point later against Spark/MapReduce, since a full-file linear scan is exactly what those frameworks parallelize.

### 1.3 — Verify the sample is correct with a spot check
Sample line *k* (for k ≥ 2) should be identical to original line *2×(k−1)*:
```bash
sed -n '5p' itineraries_sample.csv > /tmp/a.txt
sed -n '8p' itineraries.csv > /tmp/b.txt
diff /tmp/a.txt /tmp/b.txt && echo "MATCH"
```
Run for 2–3 different line numbers. All should print `MATCH`.

### 1.4 — Checksum the sample (your team's shared "is this really the same file" proof)
```bash
time md5sum itineraries_sample.csv | tee sample_checksum.txt
```
Write this checksum in `/data-prep/README.md` and in your report. If a teammate's checksum doesn't match, don't debug query results together until the checksums match.

**Log it:** `tier = 0`, `engine = md5sum`, `query_id = CHECKSUM`, `query_type = data-prep`, `wall_clock_seconds` = the `real` time.

### 1.5 — Upload the canonical sample to S3 (this is what every tier reads from)
```bash
aws s3 mb s3://<your-bucket-name>
time aws s3 cp itineraries_sample.csv s3://<your-bucket-name>/canonical/itineraries_sample.csv
aws s3 cp sample_checksum.txt s3://<your-bucket-name>/canonical/sample_checksum.txt
```
**Sanity check:** `aws s3 ls s3://<your-bucket-name>/canonical/` lists both files, CSV around ~15GB.

**Log it:** `tier = 0`, `engine = aws-cli`, `query_id = S3_UPLOAD`, `query_type = data-prep`, `wall_clock_seconds` = the `real` time for the CSV upload.

**Important:** you can now stop/terminate this EC2 instance. S3 objects persist across Learner Lab sessions, so every later tier just pulls from `s3://<your-bucket-name>/canonical/itineraries_sample.csv`.

### 1.6 — Get the sample onto local machines (once per teammate, not once per tier)
**PowerShell (Windows):**
```powershell
$t = Measure-Command { aws s3 cp s3://<your-bucket-name>/canonical/itineraries_sample.csv . }
$t.TotalSeconds
Get-FileHash itineraries_sample.csv -Algorithm MD5
```
Compare against `sample_checksum.txt` (uppercase vs lowercase, compare the hex digits).

**bash (macOS/Linux/WSL):**
```bash
time aws s3 cp s3://<your-bucket-name>/canonical/itineraries_sample.csv .
md5sum itineraries_sample.csv   # compare against sample_checksum.txt
```
**Sanity check:** hash matches exactly. If not, re-download rather than risk corrupted data.

**Log it:** `tier = 0`, `engine = aws-cli`, `query_id = LOCAL_DOWNLOAD`, `query_type = data-prep`, `wall_clock_seconds` = measured time, `node_spec` = which laptop. Do this on both laptops and log both.

Store this one local copy per laptop and reuse it for every local tier (1, 2, 3, 4). Do **not** re-download or re-sample per tier.

### 1.7 — Make a small dev subset for debugging query syntax
```bash
head -1 itineraries_sample.csv > dev_subset.csv          # header
awk 'NR>1 && $0 ~ /^[^,]*,[^,]*,2022-06/' itineraries_sample.csv >> dev_subset.csv
```
Use `dev_subset.csv` only for writing/debugging queries. Every timed, logged result must come from the full `itineraries_sample.csv` (~15GB) or the equivalent S3/HDFS/table copy.

### 1.8 — Define the fixed benchmark queries
Use these six everywhere — same logic, translated into each tier's query language.

| ID | Type | Query intent |
|---|---|---|
| Q1 | Single-row lookup | Fetch one record by `legId` |
| Q2 | Range query | All `JFK→LAX` fares under $300 in a given month |
| Q3 | Aggregation | Avg `totalFare` per route per month, across the full date range |
| Q4 | Join/enrichment | Avg fare for non-stop vs connecting flights, per route |
| Q5 | Single write | Insert one synthetic new ticket row |
| Q6 | Range write | Bulk-update `seatsRemaining` for all flights on one `flightDate` + `startingAirport` |

```sql
-- Q1
SELECT * FROM flights WHERE legId = '<sample_id>';

-- Q2
SELECT * FROM flights
WHERE startingAirport='JFK' AND destinationAirport='LAX'
  AND flightDate BETWEEN '2022-06-01' AND '2022-06-30'
  AND totalFare < 300;

-- Q3
SELECT startingAirport, destinationAirport,
       DATE_FORMAT(flightDate, '%Y-%m') AS month,
       AVG(totalFare) AS avg_fare, COUNT(*) AS n
FROM flights
GROUP BY startingAirport, destinationAirport, month
ORDER BY month;

-- Q4
SELECT startingAirport, destinationAirport, isNonStop,
       AVG(totalFare) AS avg_fare
FROM flights
GROUP BY startingAirport, destinationAirport, isNonStop;
```

Pick one concrete `legId` from `head` of your sample now and hard-code it into your Q1 scripts for every tier.

---

## Tier 1 — MySQL, vanilla (no index)

**Why:** reproduces the exact pain you already experienced — your baseline "worst case," and the number every later tier gets compared against.

### Step 1: Install
- macOS: `brew install mysql && brew services start mysql`
- Ubuntu/Debian: `sudo apt update && sudo apt install mysql-server && sudo systemctl start mysql`
- Windows: install via https://dev.mysql.com/downloads/installer/

**Sanity check:** `mysql -u root -p` connects, then `SELECT VERSION();` returns an 8.x version string.

### Step 2: Enable local file loading (needed for Step 4)
```sql
SET GLOBAL local_infile = 1;
```
Also connect with `--local-infile=1` (e.g. `mysql --local-infile=1 -u root -p`).

### Step 3: Create schema — no indexes, no primary key
```sql
CREATE DATABASE flightdb;
USE flightdb;
CREATE TABLE flights (
  legId VARCHAR(64),
  searchDate DATE,
  flightDate DATE,
  startingAirport CHAR(3),
  destinationAirport CHAR(3),
  fareBasisCode VARCHAR(32),
  travelDuration VARCHAR(16),
  elapsedDays INT,
  isBasicEconomy BOOLEAN,
  isRefundable BOOLEAN,
  isNonStop BOOLEAN,
  baseFare DECIMAL(10,2),
  totalFare DECIMAL(10,2),
  seatsRemaining INT,
  totalTravelDistance INT
  -- add segments* columns as TEXT here if you plan to use them for Q4-style joins
);
```

### Step 4: Bulk load the ~15GB sample (not row-by-row inserts)
```sql
LOAD DATA LOCAL INFILE '/path/to/itineraries_sample.csv'
INTO TABLE flights
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(legId, searchDate, flightDate, startingAirport, destinationAirport, fareBasisCode,
 travelDuration, elapsedDays, isBasicEconomy, isRefundable, isNonStop,
 baseFare, totalFare, seatsRemaining, totalTravelDistance);
```
Time this — record it in the workbook as its own row (`query_id = LOAD`). 30+ minutes is expected and is itself a data point.

**Sanity check before benchmarking:**
```sql
SELECT COUNT(*) FROM flights;
```
Compare against Section 1.2's row count. If lower, check `SHOW WARNINGS;` right after `LOAD DATA`.

### Step 5: Run and time Q1–Q6
```sql
SET profiling = 1;
-- run Q1
SHOW PROFILES;
```
Or time externally from a script (recommended, more consistent across tiers):
```python
import time, mysql.connector
conn = mysql.connector.connect(host="localhost", user="root", password="pass", database="flightdb")
cur = conn.cursor()
t0 = time.time()
cur.execute("SELECT * FROM flights WHERE legId = %s", ("<your_chosen_legId>",))
cur.fetchall()
print("Q1 time:", time.time() - t0)
```
Run Q1–Q4 (reads), then Q5 (INSERT), then Q6 (UPDATE). Log every result, `tier = 1`.

---

## Tier 2 — MySQL, indexed (+ optionally partitioned)

**Why:** isolates the effect of indexing alone — same engine, same data, same queries.

### Step 1: On the same database, add indexes matching the query patterns
```sql
ALTER TABLE flights ADD PRIMARY KEY (legId);
CREATE INDEX idx_route_date ON flights (startingAirport, destinationAirport, flightDate);
CREATE INDEX idx_fare ON flights (totalFare);
```
Time the index build itself — record as its own row (`query_id = INDEX_BUILD`).

### Step 2: Confirm the plan actually changed
```sql
EXPLAIN SELECT * FROM flights
WHERE startingAirport='JFK' AND destinationAirport='LAX'
  AND flightDate BETWEEN '2022-06-01' AND '2022-06-30' AND totalFare < 300;
```
**Expected output:** `type` column should now read `range` (using `idx_route_date`), not `ALL`. If still `ALL`, check that your `WHERE` clause's leading column matches the index's leftmost column.

### Step 3 (optional but recommended): partition by month
```sql
ALTER TABLE flights
PARTITION BY RANGE (TO_DAYS(flightDate)) (
  PARTITION p2022_04 VALUES LESS THAN (TO_DAYS('2022-05-01')),
  PARTITION p2022_05 VALUES LESS THAN (TO_DAYS('2022-06-01')),
  -- continue through the dataset's full date range (2022-04-16 to 2022-10-05)
  PARTITION p2022_11 VALUES LESS THAN MAXVALUE
);
```
**Sanity check:** `EXPLAIN` on Q2 again — look for `partitions: p2022_06` (only the relevant partition touched).

### Step 4: Re-run Q1–Q6, log as `tier = 2`.

---

## Tier 3 — DuckDB

**Why:** your "databases have come a long way" story, part one — a modern embedded columnar engine against the same vanilla-MySQL baseline. Satisfies the brief's instruction #5 (a non-big-data comparison approach).

### Step 1: Install
```bash
pip install duckdb
```
**Sanity check:** `python3 -c "import duckdb; print(duckdb.__version__)"` prints a version.

### Step 2: Query the CSV directly — no load step
```python
import duckdb, time
con = duckdb.connect()
t0 = time.time()
print(con.execute("SELECT COUNT(*) FROM 'itineraries_sample.csv'").fetchall())
print("count time:", time.time() - t0)
```
**Sanity check:** the count matches your Section 1.2 sample row count.

### Step 3: Also build a native DuckDB table
(to separate "querying CSV directly" from "querying a loaded columnar table")
```python
con.execute("CREATE TABLE flights AS SELECT * FROM 'itineraries_sample.csv'")
```

### Step 4: Run Q1–Q6 as DuckDB SQL
Once against the raw CSV and once against the native table. Log both as `tier = 3`, noting in the `engine` column which mode was used (`duckdb-csv` vs `duckdb-table`).

---

## Tier 4 — Postgres (via Docker)

**Why:** your "databases have come a long way" story, part two — a modern indexed row store with a smarter planner, same comparison basis as Tier 3.

### Step 1: Launch
```bash
docker run --name pg-flights -e POSTGRES_PASSWORD=pass -p 5432:5432 -d postgres:16
```
**Sanity check:** `docker exec -it pg-flights psql -U postgres -c "SELECT version();"` returns a Postgres 16.x string.

### Step 2: Schema + bulk load
```sql
CREATE TABLE flights ( /* same columns as Tier 1 */ );
```
```bash
docker exec -it pg-flights psql -U postgres -c "\copy flights FROM '/path/to/itineraries_sample.csv' WITH (FORMAT csv, HEADER true);"
```
(You may need to mount the CSV into the container with `-v /local/path:/data` on `docker run` so Postgres can see it.)

**Sanity check:** `SELECT COUNT(*) FROM flights;` matches the sample row count.

### Step 3: Add the same indexes as Tier 2
And optionally `PARTITION BY RANGE (flightDate)` using Postgres's native declarative partitioning.

### Step 4: Run Q1–Q6, log as `tier = 4, engine = postgres`.

**Comparison to make later:** MySQL vanilla vs MySQL indexed vs DuckDB vs Postgres indexed — same hardware, four different results. This alone is a strong mini-study before you even touch the cloud.

---

## Tier 5 — Self-managed Hadoop cluster + MapReduce (Python streaming)

**Why:** the historical baseline for distributed batch processing — shows *why* Spark was invented, by feeling the pain of the old way first.

### Step 1: Launch the cluster (Lab 2 procedure)
1. AWS Academy Learner Lab → **Start Lab** → wait for green status.
2. EC2 console → Launch 3 instances: 1 tagged `master`, 2 tagged `worker1`/`worker2`.
3. Security group: open the Hadoop ports (8088, 9870, 9000, 8020, etc. — see Lab 2's exact port list) between the three instances.
4. SSH into each; update `/etc/hosts` on all three with each other's private IPs.
5. Run the Java + Hadoop bootstrap script from Lab 2 on all three nodes.
6. Format HDFS **once**, only on the master: `hdfs namenode -format`.
7. Start HDFS + YARN: `start-dfs.sh && start-yarn.sh`.

**Sanity check:**
```bash
jps
```
Master should list `NameNode`, `ResourceManager`, `SecondaryNameNode`. Each worker should list `DataNode`, `NodeManager`.
```bash
hdfs dfsadmin -report
```
Should show 2 live DataNodes.

### Step 2: Get the sample onto HDFS (from S3, not by re-uploading from your laptop)
```bash
aws s3 cp s3://<your-bucket-name>/canonical/itineraries_sample.csv .
hdfs dfs -mkdir -p /flights
hdfs dfs -put itineraries_sample.csv /flights/
```
**Sanity check:** `hdfs dfs -ls -h /flights/` shows the file at ~15GB. `hdfs dfs -du -h /flights/` confirms replicated size.

### Step 3: Write the mapper/reducer for Q3 (aggregation — the natural MapReduce fit)
`mapper.py`:
```python
#!/usr/bin/env python3
import sys, csv
reader = csv.reader(sys.stdin)
next(reader, None)  # skip header
for row in reader:
    try:
        starting, dest, flight_date, total_fare = row[3], row[4], row[2], row[12]
        month = flight_date[:7]
        print(f"{starting},{dest},{month}\t{total_fare}")
    except (IndexError, ValueError):
        continue
```
`reducer.py`:
```python
#!/usr/bin/env python3
import sys
current_key, total, count = None, 0.0, 0
for line in sys.stdin:
    key, value = line.strip().split('\t')
    try:
        value = float(value)
    except ValueError:
        continue
    if key == current_key:
        total += value; count += 1
    else:
        if current_key is not None:
            print(f"{current_key}\t{total/count:.2f}\t{count}")
        current_key, total, count = key, value, 1
if current_key is not None:
    print(f"{current_key}\t{total/count:.2f}\t{count}")
```
Test locally before running on the cluster:
```bash
head -1000 itineraries_sample.csv | tail -999 | python3 mapper.py | sort | python3 reducer.py | head
```
**Sanity check:** output lines look like `JFK,LAX,2022-06<TAB>312.44<TAB>187` — sane fares, sane counts.

### Step 4: Run on the cluster
```bash
hadoop jar $HADOOP_HOME/share/hadoop/tools/lib/hadoop-streaming-*.jar \
  -input /flights/itineraries_sample.csv \
  -output /flights/output_q3 \
  -mapper mapper.py -reducer reducer.py \
  -file mapper.py -file reducer.py
```
Time the whole job from submission to completion (the YARN ResourceManager UI at `http://<master-public-ip>:8088` also shows job duration).

**Sanity check:** `hdfs dfs -cat /flights/output_q3/part-* | head` — same sanity shape as your local test.

Log as `tier = 5`. **Keep the cluster up** — Tier 6 reuses it. Stop the Learner Lab session (or terminate the instances) only after Tier 6 is done.

---

## Tier 6 — Self-managed Spark on YARN (same cluster as Tier 5)

**Why:** same hardware as Tier 5, same query — isolates "Spark vs MapReduce," not "cloud vs local."

### Step 1: Launch PySpark on YARN
```bash
pyspark --master yarn
```
**Sanity check:** the Spark shell banner appears with no `ERROR` lines about YARN connection failures.

### Step 2: Load and query
```python
from pyspark.sql import functions as F
import time

df = spark.read.csv("hdfs:///flights/itineraries_sample.csv", header=True, inferSchema=True)

t0 = time.time(); print(df.count()); print("count time:", time.time()-t0)

# Q1
t0 = time.time()
df.filter(F.col("legId") == "<your_chosen_legId>").show()
print("Q1 time:", time.time()-t0)

# Q3
t0 = time.time()
(df.groupBy("startingAirport", "destinationAirport",
             F.date_format("flightDate", "yyyy-MM").alias("month"))
   .agg(F.avg("totalFare").alias("avg_fare"), F.count("*").alias("n"))
   .orderBy("month")
   .show())
print("Q3 time:", time.time()-t0)
```
**Sanity check:** `df.count()` matches your Section 1.2 row count; `df.printSchema()` shows sensible types (not everything as `string`).

Note that Spark is lazy: timing only starts meaningful work at an action like `.show()`, `.count()`, or `.collect()`.

Log Q1–Q6 as `tier = 6`. **Terminate the cluster (or stop the Lab session) once Tier 6 is captured** — Tiers 7+ move to EMR.

---

## Tier 7 — EMR, single small node

**Why:** isolates "managed service overhead/convenience" from "self-managed cluster," at a similar spec to Tier 5/6.

### Step 1: Launch
1. AWS Console → **EMR** → **Create cluster**.
2. Name it, choose the latest EMR release with Spark + Hadoop applications selected.
3. Instance group: 1 node total (primary only), instance type e.g. `m5.xlarge` (verify it's in your Learner Lab's allowed list first — Console → EC2 → Launch Instance → check the instance type dropdown).
4. Key pair: none needed if using EC2 Instance Connect / Session Manager.
5. Click **Create cluster**, wait for state = **Waiting**.

**Sanity check:** cluster status reaches **Waiting** (green); SSH/Session Manager into the primary node succeeds.

### Step 2: Point Spark at S3 directly (no HDFS copy needed — this is the cloud-native pattern)
```python
df = spark.read.csv("s3://<your-bucket-name>/canonical/itineraries_sample.csv", header=True, inferSchema=True)
```

### Step 3: Run the same Q1–Q4 code as Tier 6, plus Q5/Q6 if you're testing writes back to S3 in this tier (optional — Tier 11's Iceberg table is the cleaner place for Q5/Q6).

Log as `tier = 7`. **Terminate the cluster immediately after capturing timings** (Console → EMR → select cluster → Terminate).

---

## Tier 8 — EMR, single larger node (vertical scaling)

**Why:** tests whether paying for a bigger single machine helps, before testing distribution.

### Step 1: Repeat Tier 7's launch steps, but pick a larger single instance type (e.g. `m5.4xlarge` — confirm availability in your Learner Lab first).

### Step 2: Run identical Q1–Q4 code.

Log as `tier = 8`. **Comparison point for later:** Tier 7 vs Tier 8 time, adjusted for cost, gives you a $-per-second-saved figure for vertical scaling.

---

## Tier 9 — EMR, multi-node cluster (horizontal scaling)

**Why:** the actual "does distributing help" test, and the most direct payoff of the whole project.

### Step 1: Launch a cluster with multiple core nodes, chosen so **total vCPU/RAM roughly matches Tier 8's single big node** — e.g. 4× the instance type used in Tier 7. Same total resources, different topology.

### Step 2: Run identical Q1–Q4 code.

**Sanity check:** open the Spark UI (EMR cluster's **Application user interfaces** tab, or the on-cluster history server) and confirm the job's **Executors** tab shows multiple active executors across multiple hosts.

### Step 3 (stretch): re-run Q3 with a heavier shuffle — e.g. group by all of `startingAirport, destinationAirport, flightDate, fareBasisCode` instead of just route+month — to stress the distribution more visibly.

Log as `tier = 9`. **Terminate immediately after.**

---

## Tier 10 — Spark SQL / DataFrames: joins & window functions

**Why:** the DataFrame/Spark SQL layer specifically — a separate, explicit artifact for your "Explanation of the MapReduce/Spark/SQL approach" report section. Reuse the Tier 9 cluster if it's still up; otherwise relaunch a similarly sized one.

### Step 1: Explicit join example (Q4 as a real `.join()`, not just a `groupBy`)
```python
from pyspark.sql import functions as F
from pyspark.sql.window import Window

route_avg = df.groupBy("startingAirport", "destinationAirport", "isNonStop") \
              .agg(F.avg("totalFare").alias("avg_fare"))

route_avg.show()
```

### Step 2: Window function example — rank routes by avg fare per month
```python
monthly = (df.withColumn("month", F.date_format("flightDate", "yyyy-MM"))
             .groupBy("startingAirport", "destinationAirport", "month")
             .agg(F.avg("totalFare").alias("avg_fare")))

w = Window.partitionBy("month").orderBy(F.desc("avg_fare"))
ranked = monthly.withColumn("rank", F.rank().over(w))
ranked.filter(F.col("rank") <= 5).show(50)
```

### Step 3: Capture the physical plan for your report
```python
monthly.explain(mode="formatted")
```
Copy this output into `/results/tier10_physical_plan.txt` — good evidence for the "explanation of the Spark approach" section.

Log timings as `tier = 10`.

---

## Tier 11 — Lakehouse: S3 + Glue + Iceberg

**Why:** your real answer to "range write operation." Plain CSV/Parquet on S3 can't do row-level updates — Iceberg can, with ACID guarantees. This tier is where Q5 (single write) and Q6 (range write/update) actually get demonstrated properly.

### Step 1: Crawl the S3 sample into the Glue Data Catalog
1. AWS Console → **Glue** → **Crawlers** → **Create crawler**.
2. Data source: `s3://<your-bucket-name>/canonical/`.
3. Target database: create a new Glue database, e.g. `flightdb_catalog`.
4. Run the crawler. **Sanity check:** Glue → Tables shows a new table with columns matching your CSV header.

### Step 2: Create an Iceberg table from it (on your EMR cluster, with Iceberg support)
```python
spark.sql("CREATE NAMESPACE IF NOT EXISTS glue_catalog.flights_lakehouse")
spark.sql("""
  CREATE TABLE glue_catalog.flights_lakehouse.flights
  USING iceberg
  AS SELECT * FROM glue_catalog.flightdb_catalog.<crawled_table_name>
""")
```
**Sanity check:** `spark.sql("SELECT COUNT(*) FROM glue_catalog.flights_lakehouse.flights").show()` matches your sample row count.

### Step 3: Q5 — single write
```python
spark.sql("""
  INSERT INTO glue_catalog.flights_lakehouse.flights
  VALUES ('synthetic-001', DATE'2022-07-01', DATE'2022-08-01', 'JFK', 'LAX', ...)
""")
```

### Step 4: Q6 — range write/update (the row-level update CSV/Parquet-on-S3 can't do)
```python
spark.sql("""
  UPDATE glue_catalog.flights_lakehouse.flights
  SET seatsRemaining = seatsRemaining - 1
  WHERE flightDate = DATE'2022-07-04' AND startingAirport = 'ATL'
""")
```
**Sanity check:** re-run the same `WHERE` as a `SELECT` before and after — confirm only the intended rows changed, and the affected row count is sane.

### Step 5 (bonus, cheap, and a nice concrete point for the report): time travel
```python
spark.sql("SELECT * FROM glue_catalog.flights_lakehouse.flights.history").show()
# then query a snapshot from before your Q6 update:
spark.sql("SELECT * FROM glue_catalog.flights_lakehouse.flights VERSION AS OF <snapshot_id>").show()
```
Confirms the pre-update state is still recoverable — this is the concrete "why lakehouses matter" moment.

Log Q5/Q6 timings as `tier = 11`.

---

## Tier 12 — Athena: CSV vs Parquet vs Iceberg (cost-aware SQL)

**Why:** where "format matters as much as engine" becomes obvious — same query, three storage formats, wildly different cost and latency. Extends the column-projection and partition-pruning lessons, and gives you a genuine **$-per-query** number, not just time.

### Step 1: Create three external tables over the same logical data
1. **Raw CSV**: Athena → Query editor →
   ```sql
   CREATE EXTERNAL TABLE flights_csv (
     legId string, searchDate string, flightDate string, startingAirport string,
     destinationAirport string, totalFare double, seatsRemaining int
     -- add remaining columns as needed
   )
   ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
   LOCATION 's3://<your-bucket-name>/canonical/'
   TBLPROPERTIES ('skip.header.line.count'='1');
   ```
2. **Parquet, unpartitioned**: convert with a quick Spark job first —
   ```python
   df.write.mode("overwrite").parquet("s3://<your-bucket-name>/parquet/flights_flat/")
   ```
   then `CREATE EXTERNAL TABLE flights_parquet ... STORED AS PARQUET LOCATION 's3://<your-bucket-name>/parquet/flights_flat/';`
3. **Parquet, partitioned by month**:
   ```python
   df.withColumn("month", F.date_format("flightDate", "yyyy-MM")) \
     .write.mode("overwrite").partitionBy("month") \
     .parquet("s3://<your-bucket-name>/parquet/flights_partitioned/")
   ```
   then create the external table with `PARTITIONED BY (month string)` and run `MSCK REPAIR TABLE flights_parquet_partitioned;` so Athena discovers the partitions.

**Sanity check:** `SELECT COUNT(*) FROM flights_csv;`, `..._parquet`, `..._parquet_partitioned` all return the same row count.

### Step 2: Run Q2 and Q3 against all three
For each run, note the **"Data scanned"** figure shown in the Athena query result panel (Athena bills per TB scanned; confirm the current per-TB rate on the AWS Athena pricing page before calculating estimated cost).

**Sanity check:** actual query results (row values) are identical across all three tables — only performance/cost should differ.

Log as `tier = 12`, filling in `data_scanned_MB` and `cost_estimate_usd`.

---

## Tier 13 (stretch) — Hive vs Spark SQL on the same EMR cluster

**Why:** isolates the query-engine variable specifically — identical data, identical cluster.

### Step 1: On an EMR cluster with Hive installed
```bash
hive --version
hive
```
```sql
CREATE TABLE flights_hive (...) ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
LOCATION 's3://<your-bucket-name>/canonical/';
```
Run Q3 in Hive, time it via the Hive CLI output or the YARN ResourceManager UI.

### Step 2: Run the identical query as Spark SQL on the same cluster (reuse Tier 10's setup).

Log both as `tier = 13`, noting which engine actually distributed better under Hive's execution model vs Spark's.

---

## Tier 14 (stretch) — BigQuery Sandbox

**Why:** cross-cloud comparison — same query pattern, different vendor's serverless SQL engine.

### Step 1: Set up
1. Go to https://console.cloud.google.com/bigquery, create a project, enable BigQuery Sandbox (no credit card needed for sandbox-tier usage).
2. Upload the ~15GB sample to a GCS bucket, or load directly into a BigQuery table from GCS.

### Step 2: Run Q2/Q3
Note the **"Bytes processed"** figure BigQuery shows before you run the query — the same idea as Athena's "data scanned."

Log as `tier = 14`, and compare directly against Tier 12's Athena numbers — same query, two serverless vendors.

---

## Additional comparison angles (weave into the tiers above, don't treat as separate work)

1. **Cost per query, not just time.** For every AWS tier, note EC2/EMR normalized instance-hours × the on-demand rate, or Athena/BigQuery $/TB scanned. A query that's 2× faster but 10× more expensive is a real finding — record it in `cost_estimate_usd` every time.
2. **CSV vs Parquet, format held constant, engine held constant, outside Athena.** You're already isolating format inside Tier 12 (Athena only). Also re-run at least one Spark tier (Tier 9 or 10) against the Parquet copy you created in Tier 12 Step 1, not just the raw CSV.
3. **Small-file compaction.** Simulate incremental daily loads into the Tier 11 Iceberg table (several small `INSERT`s instead of one bulk load), then run Iceberg's `CALL glue_catalog.system.rewrite_data_files('flights_lakehouse.flights')` and re-time a query before/after.

---

## AWS Learner Lab hygiene (check every single session)

- [ ] Start Lab, wait for green status, **note remaining credit before you start**
- [ ] **Note remaining credit after each session** — track burn rate
- [ ] Terminate EMR clusters and stop/terminate EC2 instances the moment you've captured timings
- [ ] Confirm allowed instance types in your Learner Lab **before** planning Tier 8/9
- [ ] S3 data persists across Lab sessions — you do **not** need to re-upload the canonical sample each time you restart the Lab

---

## When you're ready for the report

Bring back the filled-in `results_tracking_template.xlsx` and we'll turn this into the actual report: problem intro, dataset intro, MapReduce/Spark/SQL explanation, output analysis, and reflection.
