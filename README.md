# 5L Service Restart Automation

## Overview
This repository contains a Bash automation script used to safely restart critical
services in a Linux production environment while preventing service disruption
during active batch processing.

The script is designed to run unattended (via cron) and includes logging,
health checks, and AWS SNS alerting for visibility and auditability.

## Problem Statement
In the 5L production environment:
- CouchDB and PM2-based services occasionally require restarts
- Restarting services while `daily_batch.sh` is running can cause data corruption
- Manual restarts are error-prone and lack proper notification and validation

## Solution
This script automates a **safe restart workflow** by:
- Detecting active batch processes before any restart
- Blocking restarts when critical jobs are running
- Restarting CouchDB and PM2 in a controlled sequence
- Sending detailed success or failure notifications via AWS SNS
- Logging all actions for traceability

## Technologies Used
- Bash
- Linux
- systemd (CouchDB service management)
- PM2 (Node.js process manager)
- AWS SNS
- Cron
- Log monitoring

## Script Description

### `5l_service_restart.sh`

**Purpose:**  
Safely restart CouchDB and PM2 services only when it is safe to do so, with full
logging and alerting.

---

## Execution Flow (Step-by-Step)

### Step 1 — Environment Preparation
- Fixes `PATH` to ensure `pm2` works correctly when executed via cron
- Sets AWS region and logging locations

### Step 2 — Detect Running Batch Jobs
- Checks whether `daily_batch.sh` is currently running
- If found:
  - Aborts the restart
  - Sends an **URGENT SNS alert** indicating the restart was blocked
  - Exits safely without impacting running jobs

### Step 3 — Stop CouchDB
- Attempts to stop the CouchDB service using `systemctl`
- Records success or failure
- Waits 10 seconds to ensure clean shutdown

### Step 4 — Start CouchDB
- Starts CouchDB using `systemctl`
- Validates whether the start operation was successful
- Waits another 10 seconds for stabilization

### Step 5 — Restart PM2 Process
- Restarts PM2 process ID `1`
- Captures output and errors in a trail log

### Step 6 — Service Stabilization
- Waits 30 seconds to allow services to fully initialize

### Step 7 — Collect Service Status
- Captures full CouchDB service status
- Captures PM2 process status
- Stores status output for alerting and troubleshooting

### Step 8 — Send Final SNS Notification
- Sends **SUCCESS** or **FAILURE** SNS notification
- Includes:
  - Hostname
  - Timestamp
  - CouchDB service status
  - PM2 status output

---

## Logging
Logs are written to:



/mnt/custom/ops/logs/5l_service_restart.log
/mnt/custom/ops/logs/5l_service_restart_trail.txt


Logs include:
- Execution timestamps
- Service stop/start results
- PM2 restart output
- AWS SNS publish results

## AWS SNS Alerts
The script sends alerts for:
- Restart blocked due to running batch job
- Restart success
- Restart failure (with service status details)

This ensures full operational visibility without manual checking.

## How to Run
```bash
chmod +x 5l_service_restart.sh
./5l_service_restart.sh

Example Cron Schedule
0 3 * * 0 /path/5l_service_restart.sh >> /mnt/custom/ops/logs/cron.log 2>&1

Safety Features

Prevents restarts during active batch processing

Explicit service status validation

Controlled wait periods between operations

Detailed logging and alerting

Notes

Script assumes CouchDB is managed via systemd

PM2 must be installed and accessible in the configured PATH

AWS CLI must be configured with appropriate permissions

Author

Lesiba Boshomane
