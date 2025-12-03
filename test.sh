#!/usr/bin/env bash
set -euo pipefail

# --- Test Setup ---
# Create a temporary directory for the test
TEST_DIR=$(mktemp -d)
echo "Running tests in: $TEST_DIR"

# Set environment variables for the test
export MIGRATIONS_DIR="$TEST_DIR/migrations"
export SCHEMA_DUMP_FILE="$TEST_DIR/schema.sql"
DB_PATH="$TEST_DIR/test.db"

# Create the migrations directory
mkdir -p "$MIGRATIONS_DIR"

# --- Helper Functions ---
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "$expected" == "$actual" ]]; then
        echo "✅ PASSED: $message"
    else
        echo "❌ FAILED: $message"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        exit 1
    fi
}

cleanup() {
    echo "Cleaning up test directory: $TEST_DIR"
    rm -rf "$TEST_DIR"
}

# Ensure cleanup happens on exit
trap cleanup EXIT

# --- Test Cases ---

# Test: 'create' subcommand
echo ""
echo "--- Testing 'create' subcommand ---"
./migrate.sh create "create_users_table"

MIGRATION_FILE=$(find "$MIGRATIONS_DIR" -name "*_create_users_table.sql" | head -n 1)
assert_equals "1" "$(find "$MIGRATIONS_DIR" -name "*_create_users_table.sql" | wc -l | tr -d ' ')" "A single migration file should be created"
echo "Migration file created: $MIGRATION_FILE"

# Add some SQL to the migration file
echo "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);" > "$MIGRATION_FILE"

# Test: 'apply' subcommand
echo ""
echo "--- Testing 'apply' subcommand ---"
touch "$DB_PATH"
./migrate.sh apply "$DB_PATH"

# Check schema version
VERSION=$(sqlite3 "$DB_PATH" "SELECT version FROM schema_version;")
MIGRATION_VERSION=$(basename "$MIGRATION_FILE" | cut -d'_' -f1)
assert_equals "$MIGRATION_VERSION" "$VERSION" "Database schema version should be updated"

# Check if the table was created
TABLE_EXISTS=$(sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='users';")
assert_equals "users" "$TABLE_EXISTS" "The 'users' table should exist"

# Check if schema was dumped
assert_equals "1" "$(test -f "$SCHEMA_DUMP_FILE" && echo 1)" "Schema dump file should be created"
DUMP_CONTENT=$(cat "$SCHEMA_DUMP_FILE")
assert_equals "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);" "$(echo "$DUMP_CONTENT" | grep "CREATE TABLE users")" "Schema dump should contain the 'users' table"

echo ""
echo "--- All tests passed! ---"
