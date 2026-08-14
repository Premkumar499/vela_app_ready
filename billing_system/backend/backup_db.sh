#!/usr/bin/env bash
# ============================================================================
# backup_db.sh – full Supabase (PostgreSQL) database backup
#
# Usage:
#   ./backup_db.sh                 # take a full backup now
#   ./backup_db.sh --keep 14       # keep the newest 14 backups, prune older
#   ./backup_db.sh --schema-only   # backup schema without data (fast)
#   ./backup_db.sh --list          # list existing backups
#   ./backup_db.sh --restore <file>  # RESTORE a backup. .dump → pg_restore.
#                                   # .tar.gz → db_export format (see below).
#   ./backup_db.sh --health        # quick connectivity check only
#
# Cron example (weekly, Sun 02:10, keep 8):
#   10 2 * * 0  cd /home/.../billing_system/backend && ./backup_db.sh --keep 8 >> backups/backup.log 2>&1
# ============================================================================
set -euo pipefail

cd "$(dirname "$0")"

BACKUP_DIR="backups"
KEEP=7
MODE="full"
ACTION="backup"
LOG="$BACKUP_DIR/backup.log"

mkdir -p "$BACKUP_DIR"

for arg in "$@"; do
  case "$arg" in
    --schema-only) MODE="schema" ;;
    --keep) KEEP="next" ;;          # handled below in a second pass
    --list) ACTION="list" ;;
    --restore) ACTION="restore"; MODE="restore" ;;
    --health) ACTION="health" ;;
  esac
done

# --keep N  (N = the value after the flag)
if [[ "$ACTION" == "backup" ]]; then
  for i in "$@"; do :; done
  NEXT=""
  PREV=""
  for i in "$@"; do
    if [[ "$PREV" == "--keep" ]]; then NEXT="$i"; fi
    PREV="$i"
  done
  [[ -n "$NEXT" ]] && KEEP="$NEXT"
fi

# ---------------------------------------------------------------------------
# Construct a libpq-compatible URL from backend/.env (without printing secrets)
# ---------------------------------------------------------------------------
if [[ ! -f .env ]]; then
  echo "[ERROR] .env not found in $(pwd)" | tee -a "$LOG"
  exit 1
fi

DATABASE_URL=$(grep -E '^DATABASE_URL=' .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
if [[ -z "$DATABASE_URL" ]]; then
  echo "[ERROR] DATABASE_URL missing from .env" | tee -a "$LOG"
  exit 1
fi
PGURL="${DATABASE_URL/postgresql+asyncpg:\/\//postgresql:\/\/}"
PGURL="${PGURL/?ssl=require/?sslmode=require}"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

# ---------------------------------------------------------------------------
case "$ACTION" in
  health)
    if psql "$PGURL" -c "SELECT 1;" >/dev/null 2>&1; then
      echo "[$(ts)] DB HEALTH: OK"
    else
      echo "[$(ts)] DB HEALTH: FAILED"
      exit 1
    fi
    exit 0
    ;;

  list)
    echo "Backups in $BACKUP_DIR:"
    ls -lh "$BACKUP_DIR"/*.dump "$BACKUP_DIR"/*.tar.gz "$BACKUP_DIR"/*.sql 2>/dev/null | grep -v backup.log || echo "  (none)"
    exit 0
    ;;

  restore)
    FILE=""
    PREV=""
    for i in "$@"; do
      [[ "$PREV" == "--restore" ]] && FILE="$i"
      PREV="$i"
    done
    if [[ -z "$FILE" || ! -f "$BACKUP_DIR/$FILE" && ! -f "$FILE" ]]; then
      echo "Usage: ./backup_db.sh --restore <file>" | tee -a "$LOG"
      echo "Available:"
      "$0" --list
      exit 1
    fi
    [[ -f "$BACKUP_DIR/$FILE" ]] && FILE="$BACKUP_DIR/$FILE"
    if [[ "$FILE" == *.tar.gz ]]; then
      echo "[$(ts)] RESTORE (db_export format, dry listing): $FILE" | tee -a "$LOG"
      echo "This backup contains database.sql (DDL) + data/<table>.csv.gz (rows)."
      echo "To restore: extract and apply database.sql, then COPY each CSV back."
      tar -tzf "$FILE" | head -20
      exit 1
    fi
    echo "[$(ts)] RESTORING from $FILE ..." | tee -a "$LOG"
    pg_restore --clean --if-exists --no-owner --no-privileges \
      --dbname="$PGURL" "$FILE"
    echo "[$(ts)] RESTORE done." | tee -a "$LOG"
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# BACKUP
# ---------------------------------------------------------------------------
STAMP=$(date '+%Y%m%d_%H%M%S')
if [[ "$MODE" == "schema" ]]; then
  FILE="$BACKUP_DIR/schema_${STAMP}.sql"
  OPTIONS="--schema-only --format=plain"
else
  FILE="$BACKUP_DIR/full_${STAMP}.dump"
  OPTIONS="--format=custom --compress=9"
fi

echo "[$(ts)] Starting backup -> $FILE" | tee -a "$LOG"
if pg_dump $OPTIONS "$PGURL" -f "$FILE" 2>>"$LOG"; then
  SIZE=$(du -h "$FILE" | cut -f1)
  echo "[$(ts)] SUCCESS: $FILE ($SIZE)" | tee -a "$LOG"
else
  # pg_dump refuses servers NEWER than the local client (version mismatch).
  # Fall back to the version-agnostic psycopg2 exporter.
  echo "[$(ts)] pg_dump failed (likely server/client version mismatch) — switching to db_export.py" | tee -a "$LOG"
  rm -f "$FILE"
  if python3 db_export.py --out-dir "$BACKUP_DIR" 2>>"$LOG"; then
    FILE=$(ls -1t "$BACKUP_DIR"/full_*.tar.gz 2>/dev/null | head -1)
    SIZE=$(du -h "$FILE" | cut -f1)
    echo "[$(ts)] SUCCESS (db_export.py): $FILE ($SIZE)" | tee -a "$LOG"
  else
    echo "[$(ts)] FAILED: both pg_dump and db_export.py failed (details in $LOG)" | tee -a "$LOG"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Prune old backups (keep newest $KEEP backups, always keep today's)
# ---------------------------------------------------------------------------
COUNT=$(ls "$BACKUP_DIR"/full_*.dump "$BACKUP_DIR"/full_*.tar.gz 2>/dev/null | wc -l)
if [[ "$COUNT" -gt "$KEEP" ]]; then
  ls -1t "$BACKUP_DIR"/full_*.dump "$BACKUP_DIR"/full_*.tar.gz 2>/dev/null \
    | tail -n +$((KEEP + 1)) | while read -r old; do
    echo "[$(ts)] Pruning old backup: $old" | tee -a "$LOG"
    rm -f "$old"
  done
fi

echo "[$(ts)] Done. Latest backups:" | tee -a "$LOG"
ls -1ht "$BACKUP_DIR"/full_*.dump "$BACKUP_DIR"/full_*.tar.gz 2>/dev/null | head -5 | tee -a "$LOG"