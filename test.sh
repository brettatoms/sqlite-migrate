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

# Test: Schema dump excludes shadow tables and includes version INSERT
echo ""
echo "--- Testing schema dump excludes shadow tables ---"

# Create a migration with an FTS5 virtual table (use timestamp 1 second later to ensure ordering)
NEXT_TIMESTAMP=$((MIGRATION_VERSION + 1))
FTS_MIGRATION_FILE="$MIGRATIONS_DIR/${NEXT_TIMESTAMP}_add_search.sql"
cat > "$FTS_MIGRATION_FILE" << 'EOF'
CREATE VIRTUAL TABLE search_idx USING fts5(content);
EOF

./migrate.sh apply "$DB_PATH"

# Verify FTS5 shadow tables exist in the database but not in the dump
FTS_SHADOW_TABLES=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE name LIKE 'search_idx_%';")
assert_equals "1" "$(test "$FTS_SHADOW_TABLES" -gt 0 && echo 1)" "FTS5 shadow tables should exist in database"

DUMP_CONTENT=$(cat "$SCHEMA_DUMP_FILE")
SHADOW_IN_DUMP=$(echo "$DUMP_CONTENT" | grep -c "search_idx_" || true)
assert_equals "0" "$SHADOW_IN_DUMP" "Schema dump should NOT contain FTS5 shadow tables"

# Verify the virtual table itself IS in the dump
assert_equals "1" "$(echo "$DUMP_CONTENT" | grep -c "CREATE VIRTUAL TABLE search_idx" || true)" "Schema dump should contain the FTS5 virtual table"

# Verify schema version INSERT is in the dump
assert_equals "1" "$(echo "$DUMP_CONTENT" | grep -c "INSERT INTO \"schema_version\".*$NEXT_TIMESTAMP" || true)" "Schema dump should contain INSERT for schema version"

echo ""
echo "--- All tests passed! ---"
