#!/usr/bin/env fish

function usage
    echo "Usage:"
    echo "  backup.fish -f <user:pass@host:port/db> -t <user:pass@host:port/db> [options]"
    echo ""
    echo "Options:"
    echo "  -f, --from           Source DB connection string"
    echo "  -t, --to             Destination DB connection string"
    echo "  -o, --outdir         Output directory or full .sql file path"
    echo "  -l, --log-file       Log file path (default: stdout)"
    echo "  -c, --clean-restore  Drop destination DB first (asks for confirmation)"
    echo "  -h, --help           Show this help"
end

function die
    echo "Error: $argv" >&2
    exit 1
end

function parse_conn
    set -l prefix $argv[1]
    set -l conn $argv[2]
    set -l match (string match -r '^([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+)$' -- $conn)
    if test (count $match) -lt 6
        die "Invalid connection string for $prefix"
    end
    set -g {$prefix}_USER $match[2]
    set -g {$prefix}_PASS $match[3]
    set -g {$prefix}_HOST $match[4]
    set -g {$prefix}_PORT $match[5]
    set -g {$prefix}_DB $match[6]
end

argparse --name backup \
    'f/from=' 't/to=' 'o/outdir=' 'l/log-file=' 'c/clean-restore' 'h/help' -- $argv
or begin
    usage
    exit 1
end

if set -q _flag_help
    usage
    exit 0
end

if not set -q _flag_from
    die "--from is required"
end
if not set -q _flag_to
    die "--to is required"
end

set -l from_conn $_flag_from
set -l to_conn $_flag_to
set -l out_param ""
set -l log_file ""
set -l clean_restore 0

if set -q _flag_outdir
    set out_param $_flag_outdir
end
if set -q _flag_log_file
    set log_file $_flag_log_file
end
if set -q _flag_clean_restore
    set clean_restore 1
end

parse_conn "FROM" $from_conn
parse_conn "TO" $to_conn

set -l timestamp (date "+%Y%m%d-%H%M%S")
set -l out_dir ""
set -l out_file ""
if test -n "$out_param"
    if string match -r '\.sql$' -- $out_param
        set out_file $out_param
        set out_dir (dirname $out_file)
    else
        set out_dir $out_param
        set out_file "$out_dir/dump-$FROM_DB-$timestamp.sql"
    end
else
    set out_dir "$HOME/backup-db"
    set out_file "$out_dir/dump-$FROM_DB-$timestamp.sql"
end

mkdir -p $out_dir

if test -n "$log_file"
    mkdir -p (dirname $log_file)
    exec >$log_file 2>&1
end

if test $clean_restore -eq 1
    read -l -P "This will drop destination database '$TO_DB'. Type 'y' to continue: " confirm
    if test "$confirm" != "y"
        die "Aborted by user"
    end
end

echo "Dumping source database to $out_file"
env PGPASSWORD=$FROM_PASS pg_dump \
    -h $FROM_HOST -p $FROM_PORT -U $FROM_USER \
    --inserts --no-privileges --no-owner --clean --create --if-exists \
    $FROM_DB > $out_file
or die "pg_dump failed"

if test $clean_restore -eq 1
    echo "Dropping destination database $TO_DB"
    env PGPASSWORD=$TO_PASS psql \
        -h $TO_HOST -p $TO_PORT -U $TO_USER -d postgres -v ON_ERROR_STOP=1 \
        -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$TO_DB' AND pid <> pg_backend_pid();" \
        -c "DROP DATABASE IF EXISTS \"$TO_DB\";"
    or die "Failed to drop destination database"
end

echo "Restoring dump into destination server"
env PGPASSWORD=$TO_PASS psql \
    -h $TO_HOST -p $TO_PORT -U $TO_USER -d postgres -v ON_ERROR_STOP=1 \
    -f $out_file
or die "Restore failed"

echo "Done"
