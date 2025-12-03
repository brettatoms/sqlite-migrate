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

init_schema_version_table() {
    local db_path="$1"

    # Create the schema version table if it doesn't exist
    sqlite3 "$db_path" "CREATE TABLE IF NOT EXISTS \"$SCHEMA_VERSION_TABLE\" (version TEXT NOT NULL);"

    # Check if a version is present
    local count
    count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM \"$SCHEMA_VERSION_TABLE\";")

    # If no version is present, insert initial version '0'
    if [[ "$count" -eq 0 ]]; then
        sqlite3 "$db_path" "INSERT INTO \"$SCHEMA_VERSION_TABLE\" (version) VALUES ('0');"
    fi
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
    current_version=$(sqlite3 "$db_path" "SELECT version FROM \"$SCHEMA_VERSION_TABLE\" LIMIT 1;")
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
                echo "UPDATE \"$SCHEMA_VERSION_TABLE\" SET version = '$version';"
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
        sqlite3 "$db_path" '.dump' >"$SCHEMA_DUMP_FILE"
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
