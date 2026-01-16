# pgsql-sync

Simple cross-shell PostgreSQL backup/restore scripts that mirror common DBeaver
export options (SQL INSERTs, no privileges/owner, include drop/create database).

## IMPORTANT

I personally uses fish shell, so the `bash` and `pwsh` script were not tested yet 😅.
This exist becaus i'm tired with the hard-to-click GUI desktop app. Yup, all the code is written by GPT-5.2 Codex.
I'm just write the instruction

## Scripts

- `backup.sh` (bash)
- `backup.fish` (fish)
- `backup.ps1` (PowerShell)

## Requirements

- `pg_dump` and `psql` available in `PATH`
- Network access to both PostgreSQL servers
- Permission to `DROP DATABASE` if `--clean-restore` is used

## Connection string format

```
<username>:<password>@<host>:<port>/<db_name>
```

Example:

```
myuser:mypass@127.0.0.1:5432/mydb
```

## Usage

```
backup.sh  -f "<user:pass@host:port/db>" -t "<user:pass@host:port/db>" [options]
backup.fish -f "<user:pass@host:port/db>" -t "<user:pass@host:port/db>" [options]
backup.ps1 -f "<user:pass@host:port/db>" -t "<user:pass@host:port/db>" [options]
```

Options:

- `-f, --from` Source DB connection string (required)
- `-t, --to` Destination DB connection string (required)
- `-o, --outdir` Output directory or full `.sql` file path
- `-l, --log-file` Log file path (default: stdout)
- `-c, --clean-restore` Drop destination DB first (asks for confirmation)

## Output location

Default output is:

```
$HOME/backup-db/dump-<db_name>-<timestamp>.sql
```

If `--outdir` ends with `.sql`, it is treated as a full file path. Otherwise,
it is treated as a directory.

## Examples

Backup and restore with defaults:

```
./backup.sh -f "src_user:src_pass@db1.local:5432/app" -t "dst_user:dst_pass@db2.local:5432/app"
```

Specify output directory and log file:

```
./backup.fish -f "u:p@db1.local:5432/app" -t "u:p@db2.local:5432/app" \
  -o "$HOME/backup-db" -l "$HOME/backup-db/backup.log"
```

Overwrite destination DB (asks for confirmation):

```
./backup.ps1 -f "u:p@db1.local:5432/app" -t "u:p@db2.local:5432/app" -c
```

## Notes

- `--clean-restore` asks for a single-character confirmation (`y`).
- The SQL dump includes `CREATE DATABASE` and `DROP DATABASE IF EXISTS`.
  This means the destination database name will match the source database name.
  If you need to restore into a different database name, remove `--create` and
  `--clean` in the scripts or run `psql` into a specific target database.

## Author

- GitHub: https://github.com/AdiCahyaSaputra
- GPT-5.2 Codex