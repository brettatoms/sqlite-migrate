# AGENTS.md

## Project Overview

This repository contains a simple, dependency-free bash script for managing SQLite database migrations. The script is designed to be a lightweight and portable tool for projects using SQLite.

## Tech Stack

- **Language:** Bash

## Key Files

- `bin/migrate.sh`: The main executable script.

## Common Commands

The script uses subcommands to perform actions.

### Create a Migration

```bash
# Creates a new migration file in the directory specified by $MIGRATIONS_DIR (default: migrations/)
$ bin/migrate.sh create <migration_name>
```

### Apply Migrations

```bash
# Applies all pending migrations to the specified database.
$ bin/migrate.sh apply <database_path>
```

### Environment Variables

- `MIGRATIONS_DIR`: The directory where migration files are stored. Defaults to `migrations/`.
- `SCHEMA_VERSION_TABLE`: The name of the table used to track schema versions. Defaults to `schema_version`.
- `SCHEMA_DUMP_FILE`: The file path where the full database schema is dumped after migrations are applied. Defaults to `./schema.sql`. To disable, set this to `/dev/null`.
