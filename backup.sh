#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  backup.sh -f <user:pass@host:port/db> -t <user:pass@host:port/db> [options]

Options:
  -f, --from           Source DB connection string
  -t, --to             Destination DB connection string
  -o, --outdir         Output directory or full .sql file path
  -l, --log-file       Log file path (default: stdout)
  -c, --clean-restore  Drop destination DB first (asks for confirmation)
  -h, --help           Show this help
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

parse_conn() {
  local prefix="$1"
  local conn="$2"
  if [[ ! "$conn" =~ ^([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+)$ ]]; then
    die "Invalid connection string for $prefix"
  fi
  eval "${prefix}_USER='${BASH_REMATCH[1]}'"
  eval "${prefix}_PASS='${BASH_REMATCH[2]}'"
  eval "${prefix}_HOST='${BASH_REMATCH[3]}'"
  eval "${prefix}_PORT='${BASH_REMATCH[4]}'"
  eval "${prefix}_DB='${BASH_REMATCH[5]}'"
}

FROM_CONN=""
TO_CONN=""
OUT_PARAM=""
LOG_FILE=""
CLEAN_RESTORE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--from)
      FROM_CONN="${2:-}"; shift 2 ;;
    -t|--to)
      TO_CONN="${2:-}"; shift 2 ;;
    -o|--outdir)
      OUT_PARAM="${2:-}"; shift 2 ;;
    -l|--log-file)
      LOG_FILE="${2:-}"; shift 2 ;;
    -c|--clean-restore)
      CLEAN_RESTORE=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown argument: $1" ;;
  esac
done

[[ -n "$FROM_CONN" ]] || die "--from is required"
[[ -n "$TO_CONN" ]] || die "--to is required"

parse_conn "FROM" "$FROM_CONN"
parse_conn "TO" "$TO_CONN"

timestamp="$(date +"%Y%m%d-%H%M%S")"
if [[ -n "$OUT_PARAM" ]]; then
  if [[ "$OUT_PARAM" == *.sql ]]; then
    OUTFILE="$OUT_PARAM"
    OUTDIR="$(dirname "$OUTFILE")"
  else
    OUTDIR="$OUT_PARAM"
    OUTFILE="$OUTDIR/dump-${FROM_DB}-${timestamp}.sql"
  fi
else
  OUTDIR="$HOME/backup-db"
  OUTFILE="$OUTDIR/dump-${FROM_DB}-${timestamp}.sql"
fi
mkdir -p "$OUTDIR"

if [[ -n "$LOG_FILE" ]]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  exec >"$LOG_FILE" 2>&1
fi

if $CLEAN_RESTORE; then
  read -r -p "This will drop destination database '${TO_DB}'. Type 'y' to continue: " confirm
  if [[ "$confirm" != "y" ]]; then
    die "Aborted by user"
  fi
fi

echo "Dumping source database to $OUTFILE"
PGPASSWORD="$FROM_PASS" pg_dump \
  -h "$FROM_HOST" -p "$FROM_PORT" -U "$FROM_USER" \
  --inserts --no-privileges --no-owner --clean --create --if-exists \
  "$FROM_DB" > "$OUTFILE"

if $CLEAN_RESTORE; then
  echo "Dropping destination database ${TO_DB}"
  PGPASSWORD="$TO_PASS" psql \
    -h "$TO_HOST" -p "$TO_PORT" -U "$TO_USER" -d postgres -v ON_ERROR_STOP=1 \
    -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$TO_DB' AND pid <> pg_backend_pid();" \
    -c "DROP DATABASE IF EXISTS \"${TO_DB}\";"
fi

echo "Restoring dump into destination server"
PGPASSWORD="$TO_PASS" psql \
  -h "$TO_HOST" -p "$TO_PORT" -U "$TO_USER" -d postgres -v ON_ERROR_STOP=1 \
  -f "$OUTFILE"

echo "Done"
