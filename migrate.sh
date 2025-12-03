#!/usr/bin/env bash
set -euo pipefail

# Default schema version table name, can be overridden by environment variable
: "${SCHEMA_VERSION_TABLE:=schema_version}"
# Default migrations directory, can be overridden by environment variable
: "${MIGRATIONS_DIR:=migrations/}"
# Default schema dump file path, can be overridden by environment variable
: "${SCHEMA_DUMP_FILE:=./schema.sql}"

usage() {
    echo "Usage: $0 <subcommand> [options]"
    echo ""
    echo "Subcommands:"
    echo "  apply <db_path>   Apply pending migrations"
    echo "  create <name>      Create a new migration file"
    echo ""
    echo "Environment Variables:"
    echo "  MIGRATIONS_DIR: Directory containing migration files (default: migrations/)"
    echo "  SCHEMA_DUMP_FILE: File path to dump the schema to after applying migrations (default: ./schema.sql)."
    echo "  SCHEMA_VERSION_TABLE: Name of the table to store schema version (default: schema_version)"
    exit 1
}

dump_schema() {
    local db_path="$1"

    # Dump schema from sqlite_master, excluding:
    # 1. sqlite_* internal tables
    # 2. Shadow tables created by virtual tables (FTS3/4/5, R-Tree)
    sqlite3 "$db_path" "
SELECT sql || ';' FROM sqlite_master
WHERE sql IS NOT NULL
  AND name NOT LIKE 'sqlite_%'
  AND name NOT IN (
    SELECT vt.name || '_' || s.suffix
    FROM (SELECT name FROM sqlite_master WHERE sql LIKE 'CREATE VIRTUAL TABLE%') vt
    CROSS JOIN (
      SELECT 'content' AS suffix UNION ALL SELECT 'data' UNION ALL SELECT 'docsize'
      UNION ALL SELECT 'idx' UNION ALL SELECT 'config' UNION ALL SELECT 'segments'
      UNION ALL SELECT 'segdir' UNION ALL SELECT 'stat' UNION ALL SELECT 'node'
      UNION ALL SELECT 'parent' UNION ALL SELECT 'rowid'
    ) s
  )
ORDER BY CASE type WHEN 'table' THEN 1 WHEN 'index' THEN 2 WHEN 'trigger' THEN 3 WHEN 'view' THEN 4 END;
"
    # Add INSERTs for all schema versions so loading this schema marks the database as migrated
    sqlite3 "$db_path" "SELECT 'INSERT INTO \"$SCHEMA_VERSION_TABLE\" (version) VALUES (''' || version || ''');' FROM \"$SCHEMA_VERSION_TABLE\" ORDER BY version;"
}

init_schema_version_table() {
    local db_path="$1"

    # Create the schema version table if it doesn't exist
    sqlite3 "$db_path" "CREATE TABLE IF NOT EXISTS \"$SCHEMA_VERSION_TABLE\" (version TEXT NOT NULL);"
}

apply_migrations() {
    local db_path="$1"
    local migrations_applied=0

    if [[ ! -f "$db_path" ]]; then
        echo "Error: Database file not found at $db_path"
        exit 1
    fi

    if [[ ! -d "$MIGRATIONS_DIR" ]]; then
        echo "Error: Migrations directory not found at $MIGRATIONS_DIR"
        exit 1
    fi

    # Ensure sqlite3 is available
    if ! command -v sqlite3 &>/dev/null; then
        echo "Error: sqlite3 command not found. Please install it."
        exit 1
    fi

    init_schema_version_table "$db_path"

    local current_version
    current_version=$(sqlite3 "$db_path" "SELECT COALESCE(MAX(version), '0') FROM \"$SCHEMA_VERSION_TABLE\";")
    echo "Current database version: $current_version"

    # Find, sort, and loop through migration files
    local migrations
    migrations=$(find "$MIGRATIONS_DIR" -maxdepth 1 -name "*.sql" | sort -V)

    if [[ -z "$migrations" ]]; then
        echo "No migration files found in $MIGRATIONS_DIR."
        exit 0
    fi

    for migration_file in $migrations; do
        local filename
        filename=$(basename "$migration_file")
        local version
        version=$(echo "$filename" | cut -d'_' -f1)

        # Compare versions lexicographically
        if [[ "$version" > "$current_version" ]]; then
            migrations_applied=1
            echo "Applying migration: $filename"

            # Apply migration and update version in a single transaction
            if (
                echo "BEGIN TRANSACTION;"
                cat "$migration_file"
                echo "INSERT INTO \"$SCHEMA_VERSION_TABLE\" (version) VALUES ('$version');"
                echo "COMMIT;"
            ) | sqlite3 "$db_path"; then
                echo "Successfully applied migration version $version"
                current_version="$version" # Update current version for the next iteration
            else
                echo "Error: Failed to apply migration version $version. Rolling back."
                exit 1
            fi
        fi
    done

    if [[ "$migrations_applied" -eq 1 ]]; then
        echo "All pending migrations have been applied."
        echo "Dumping schema to $SCHEMA_DUMP_FILE"
        dump_schema "$db_path" >"$SCHEMA_DUMP_FILE"
        echo "Schema dumped successfully."
    else
        echo "Database is already up to date."
    fi
}

create_migration() {
    local name="$1"

    if [[ ! -d "$MIGRATIONS_DIR" ]]; then
        echo "Error: Migrations directory not found at $MIGRATIONS_DIR"
        echo "Please create it first: mkdir -p $MIGRATIONS_DIR"
        exit 1
    fi

    local timestamp
    timestamp=$(date +%Y%m%d%H%M%S)
    local safe_name
    safe_name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '_' | sed 's/[^a-z0-9_]//g')

    local filename="${timestamp}_${safe_name}.sql"
    local filepath="$MIGRATIONS_DIR/$filename"

    # Create the migration file with a placeholder comment
    {
        echo "-- Migration: $name"
        echo "-- Version: $timestamp"
        echo ""
        echo "-- Add your SQL statements here"
    } >"$filepath"

    echo "Created new migration file: $filepath"
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    local subcommand="$1"
    shift

    case "$subcommand" in
    apply)
        if [[ $# -ne 1 ]]; then
            echo "Error: 'apply' command requires a <db_path> argument."
            usage
        fi
        apply_migrations "$1"
        ;;
    create)
        if [[ $# -ne 1 ]]; then
            echo "Error: 'create' command requires a <name> argument."
            usage
        fi
        create_migration "$1"
        ;;
    *)
        echo "Error: Unknown subcommand '$subcommand'"
        usage
        ;;
    esac
}

main "$@"
