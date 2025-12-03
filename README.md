# Simple SQLite Migrator

A simple, dependency-free bash script for managing SQLite database migrations.

This script provides a straightforward way to version your SQLite database schema. It is designed to be lightweight and easy to integrate into any project that uses SQLite.

> [!NOTE]
> The code in this repo was generated almost entirely with AI.

## What it does (and doesn't do)

-   **Simple and Focused:** The script is intentionally simple. It supports one-way migrations (upgrades) and creating new migration files.
-   **SQLite Only:** It is designed specifically for SQLite and uses the `sqlite3` command-line tool.
-   **Forward-Only Migrations:** There is no support for rollbacks or downgrades. This keeps the logic simple and predictable.
-   **Timestamp-based Ordering:** Migrations are ordered based on a Unix timestamp prefix in the filename, ensuring they are applied in the order they were created.

## Usage

The script is executed via the `bin/migrate` command, which takes a subcommand.

```
./bin/migrate <subcommand> [options]
```

### Subcommands

-   `create <name>`: Creates a new migration file with a timestamp prefix in the migrations directory.
-   `apply <db_path>`: Applies all pending migrations to the specified SQLite database file. After migrations are applied, the full database schema is dumped to the file specified by the `SCHEMA_DUMP_FILE` environment variable.

### Environment Variables

The script's behavior can be configured with the following environment variables:

-   `MIGRATIONS_DIR`: The directory containing your migration files.
    -   **Default:** `migrations/`
-   `SCHEMA_VERSION_TABLE`: The name of the table used to track the current schema version.
    -   **Default:** `schema_version`
- `SCHEMA_DUMP_FILE`: The file path to dump the full database schema to after migrations are successfully applied.
    -   **Default:** `./schema.sql`

> [!TIP]
> To disable dumping the schema to a file, you can set `SCHEMA_DUMP_FILE` to `/dev/null`. For example:
> `SCHEMA_DUMP_FILE=/dev/null ./bin/migrate apply my_app.db`


## Examples

### 1. Creating a Migration

To create a new migration file, use the `create` subcommand.

```bash
$ ./bin/migrate create add_users_table
Created new migration file: migrations/1678886400_add_users_table.sql
```

You can then add your SQL statements to the generated file:

```sql
-- migrations/1678886400_add_users_table.sql
-- Migration: add_users_table
-- Version: 1678886400

CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    email TEXT NOT NULL UNIQUE
);
```

### 2. Applying Migrations

To apply pending migrations to your database, use the `apply` subcommand.

```bash
$ ./bin/migrate apply my_app.db
Current database version: 0
Applying migration: 1678886400_add_users_table.sql
Successfully applied migration version 1678886400
All pending migrations have been applied.
```

If the database is already up to date, no action will be taken:

```bash
$ ./bin/migrate apply my_app.db
Current database version: 1678886400
Database is already up to date.
```


