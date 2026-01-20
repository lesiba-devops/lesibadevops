#!/bin/bash

# Fix PATH for cron so pm2 works
export PATH=$PATH:/home/kallio/.nvm/versions/node/v12.16.3/bin

# =======================================================================
# Script Name: 5l Service Restart Automation (Updated)
# Description:
#   • Checks if daily_batch.sh is running → if yes, abort + send SNS blocked alert.
#   • If not running → STOP CouchDB, wait 10s, START CouchDB, wait 10s → restart PM2.
#   • Includes explicit CouchDB status in SNS (CRITICAL requirement).
#   • Sends SUCCESS or FAILURE SNS alerts.
#   • Ensures correct AWS profile + region handling.
# Author: Lesiba Boshomane
# Updated: 07-Dec-2025
# =======================================================================

LOG_DIR="/mnt/custom/ops/logs"
LOG_FILE="${LOG_DIR}/5l_service_restart.log"
TRAIL_FILE="${LOG_DIR}/5l_service_restart_trail.txt"
DAILY_SCRIPT="daily_batch.sh"
SNS_TOPIC_ARN="<AWS_SNS_TOPIC_ARN>"
#Sensitive values ("ARNs") have been intentionally redacted.
AWS_REGION="ap-southeast-2"
export AWS_REGION

mkdir -p "$LOG_DIR"

{
    echo "=============================================================="
    echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] Starting service restart check..."

    # --------------------------------------------------------------
    # STEP 1 — Detect running daily_batch.sh
    # --------------------------------------------------------------
    RUNNING=$(pgrep -f "$DAILY_SCRIPT")

    if [ -n "$RUNNING" ]; then
        echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] DAILY BATCH FOUND RUNNING! PID(s): $RUNNING"
        echo "[5L] Aborting service restart."

        MESSAGE="Service restart blocked on 5L-Prod.

daily_batch.sh is still running.
PID(s): $RUNNING
Host: $(hostname)
Time: $(date '+%Y-%m-%d %H:%M:%S')"

        aws sns publish \
            --topic-arn "$SNS_TOPIC_ARN" \
            --subject "URGENT: 5L Prod restart BLOCKED — daily_batch running" \
            --message "$MESSAGE" \
            --region "$AWS_REGION" >> "$LOG_FILE" 2>&1

        echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] SNS alert sent (restart blocked)."
        echo "=============================================================="
        exit 0
    fi

    echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] No daily batch running. Proceeding..."

    # --------------------------------------------------------------
    # STEP 2 — STOP CouchDB
    # --------------------------------------------------------------
    echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] Stopping CouchDB..."
    FAIL=false

    if sudo systemctl stop couchdb >> "$LOG_FILE" 2>&1; then
        echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] CouchDB stopped successfully."
    else
        echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] ERROR: CouchDB STOP failed!"
        FAIL=true
    fi

    sleep 10

    # --------------------------------------------------------------
    # STEP 3 — START CouchDB
    # --------------------------------------------------------------
    echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] Starting CouchDB..."

    if sudo systemctl start couchdb >> "$LOG_FILE" 2>&1; then
        echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] CouchDB started successfully."
    else
        echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] ERROR: CouchDB START failed!"
        FAIL=true
    fi

    sleep 10

    # --------------------------------------------------------------
    # STEP 4 — Restart PM2 Process 1
    # --------------------------------------------------------------
    echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] Restarting PM2 process 1..."

    if pm2 restart 1 >> "$TRAIL_FILE" 2>&1; then
        echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] PM2 process restarted successfully."
    else
        echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] ERROR: PM2 restart FAILED!"
        FAIL=true
    fi

    # --------------------------------------------------------------
    # STEP 5 — Wait 30 seconds
    # --------------------------------------------------------------
    echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] Waiting 30 seconds before SNS..."
    sleep 30

    # --------------------------------------------------------------
    # STEP 6 — Collect service status (FIXED WITH 2>&1)
    # --------------------------------------------------------------
    STATUS_COUCHDB=$(systemctl status couchdb --no-pager 2>&1)
    STATUS_PM2=$(pm2 status 2>&1)

    echo "$STATUS_COUCHDB" > "$TRAIL_FILE"
    echo "" >> "$TRAIL_FILE"
    echo "$STATUS_PM2" >> "$TRAIL_FILE"

    # --------------------------------------------------------------
    # STEP 7 — Send SNS success/failure
    # --------------------------------------------------------------
    if [ "$FAIL" = true ]; then
        SUBJECT="URGENT: 5L service RESTART FAILED — Immediate Action Needed"
        BODY="One or 5Lre service restart operations FAILED.

Host: $(hostname)
Time: $(date '+%Y-%m-%d %H:%M:%S')

CouchDB Status:
$STATUS_COUCHDB

PM2 Status:
$STATUS_PM2"
    else
        SUBJECT="5L: Services restarted SUCCESSFULLY — No Action Needed"
        BODY="All 5L services restarted successfully.

CouchDB Status:
$STATUS_COUCHDB

PM2 Status:
$STATUS_PM2"
    fi

    aws sns publish \
        --topic-arn "$SNS_TOPIC_ARN" \
        --subject "$SUBJECT" \
        --message "$BODY" \
        --region "$AWS_REGION" >> "$LOG_FILE" 2>&1

    echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] SNS alert sent."
    echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] [5L] Service restart routine completed."
    echo "=============================================================="

} >> "$LOG_FILE" 2>&1

