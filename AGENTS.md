# AGENTS.md

## Project Overview

This repository contains a simple, dependency-free bash script for managing SQLite database migrations. The script is designed to be a lightweight and portable tool for projects using SQLite.

## Tech Stack

- **Language:** Bash

## Key Files

- `bin/migrate`: The main executable script.

## Common Commands

The script uses subcommands to perform actions.

### Create a Migration

```bash
# Creates a new migration file in the directory specified by $MIGRATIONS_DIR (default: migrations/)
$ bin/migrate create <migration_name>
```

### Apply Migrations

```bash
# Applies all pending migrations to the specified database.
$ bin/migrate apply <database_path>
```

### Environment Variables

- `MIGRATIONS_DIR`: The directory where migration files are stored. Defaults to `migrations/`.
- `SCHEMA_VERSION_TABLE`: The name of the table used to track schema versions. Defaults to `schema_version`.
- `SCHEMA_DUMP_FILE`: If set, the full database schema will be dumped to this file path after migrations are applied. Defaults to `./schema.sql`.
