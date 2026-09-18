---
title: Migrations - Aim ORM
description: Database migrations with Aim CLI. Auto-generate migration SQL from schema changes, apply and rollback migrations.
head:
  - - meta
    - name: keywords
      content: Dart migrations, database migrations, aim_cli, schema diff, SQL generation
---

# Migrations

Aim CLI provides powerful database migration tools that automatically generate SQL from your schema changes.

## Overview

The migration workflow:

1. **Define schema** - Write your table definitions using Dart Records
2. **Generate migration** - `aim db:generate` detects changes and creates SQL
3. **Apply migration** - `aim db:migrate` runs the SQL against your database
4. **Rollback if needed** - `aim db:rollback` reverts changes

## Setup

### 1. Configure Database

Add database configuration to your `pubspec.yaml`:

```yaml
name: my_app

dependencies:
  aim_server: ^0.1.0
  aim_orm: ^0.1.0
  aim_orm_postgres: ^0.1.0
  aim_postgres: ^0.1.0

aim:
  database:
    url: ${DATABASE_URL:postgresql://localhost:5432/mydb}
    schema: lib/schema.dart  # Path to your schema file
```

| Option | Description | Default |
|--------|-------------|---------|
| `url` | Database connection URL | Required |
| `schema` | Path to schema definitions, a file or a directory | `lib/schema` |

Or set database URL via environment variable:

```bash
export DATABASE_URL="postgresql://user:pass@localhost:5432/mydb"
```

### 2. Create Schema File

Create `lib/schema.dart`:

```dart
import 'package:aim_orm/aim_orm.dart';
import 'package:aim_orm_postgres/aim_orm_postgres.dart';

part 'schema.g.dart';

@PgTable('users')
final users = (
  id: uuid('id').primaryKey(),
  email: varchar('email', length: 255).unique(),
  name: varchar('name', length: 255),
  createdAt: timestamp('created_at').withDefaultNow(),
);

@PgTable('posts')
final posts = (
  id: uuid('id').primaryKey(),
  userId: uuid('user_id'),
  title: varchar('title', length: 255),
  content: text('content').nullable(),
  publishedAt: timestamp('published_at').nullable(),
  createdAt: timestamp('created_at').withDefaultNow(),
);
```

## Generating Migrations

### Basic Usage

```bash
aim db:generate
```

This compares your current schema with the last migration and generates SQL for the differences.

### With Custom Name

```bash
aim db:generate --name add_posts_table
```

### Output

Migrations are created in the `migrations/` directory:

```
migrations/
├── 20250121_100000_initial.sql
├── 20250121_110000_add_posts_table.sql
└── 20250121_120000_add_indexes.sql
```

### Migration File Format

Each migration file contains both UP and DOWN sections:

```sql
-- UP
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  name VARCHAR(255) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE posts (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  title VARCHAR(255) NOT NULL,
  content TEXT,
  published_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- DOWN
DROP TABLE posts;
DROP TABLE users;
```

## Detected Changes

`aim db:generate` automatically detects:

### Table Operations
- **CREATE TABLE** - New table definitions
- **DROP TABLE** - Removed table definitions

### Column Operations
- **ADD COLUMN** - New columns added to existing tables
- **DROP COLUMN** - Columns removed from tables
- **RENAME COLUMN** - Column renames (detected interactively)
- **ALTER COLUMN TYPE** - Data type changes
- **SET NOT NULL / DROP NOT NULL** - Nullability changes
- **SET DEFAULT / DROP DEFAULT** - Default value changes

### Constraints
- **ADD/DROP UNIQUE** - Unique constraints
- **ADD/DROP INDEX** - Indexes
- **ADD/DROP FOREIGN KEY** - Foreign key constraints

### Constraint Names

Foreign keys and unique constraints are created with a name this tool
chooses: `fk_<table>_<column>` and `uq_<table>_<column>`. The migration
that removes one later looks for that name, and also for the name Postgres
gives a constraint created without one (`<table>_<column>_fkey` and
`<table>_<column>_key`), so a database created before this naming existed
can still be migrated.

Primary keys stay on the column and are never dropped by a generated
migration.

### How a Reference Is Read

`references(() => users.id)` names a Dart variable and a record field. The
table name comes from the `@PgTable` annotation on that variable, and the
column name from the column definition, so neither has to match what the
Dart code calls it:

```dart
@PgTable('ord_users')
final ordUsers = (
  key: integer('user_key').primaryKey(),
);

@PgTable('ord_posts')
final ordPosts = (
  id: integer('id').primaryKey(),
  owner: integer('owner_key').references(() => ordUsers.key),
);
```

generates `REFERENCES ord_users(user_key)`.

::: warning
A reference whose variable is not an `@PgTable` in the scanned schema path,
or whose field does not exist on the table it names, stops `aim db:generate`
with an error naming the file, the column and what was written. Carrying
the Dart name through would produce SQL naming a relation the database does
not have, and that only surfaces when the migration is applied.

The same is true when that variable is declared in more than one file and
none of the declarations sits in the file that wrote the reference: with
nothing to choose between them, the command stops rather than guess which
one was meant. A schema where two records carry the same `@PgTable` name
stops it as well, since a reference to that name could not say which one it
meant either.
:::

Changing where a reference points, or its `onDelete` or `onUpdate`, drops
the constraint and adds it back: Postgres has no statement that repoints a
foreign key.

### Example: Adding a Column

Before:
```dart
@PgTable('users')
final users = (
  id: uuid('id').primaryKey(),
  email: varchar('email', length: 255).unique(),
);
```

After:
```dart
@PgTable('users')
final users = (
  id: uuid('id').primaryKey(),
  email: varchar('email', length: 255).unique(),
  name: varchar('name', length: 255),  // New column
);
```

Generated migration:
```sql
-- UP
ALTER TABLE users ADD COLUMN name VARCHAR(255) NOT NULL;

-- DOWN
ALTER TABLE users DROP COLUMN name;
```

### Example: Making Column Nullable

Before:
```dart
title: varchar('title', length: 255),
```

After:
```dart
title: varchar('title', length: 255).nullable(),
```

Generated migration:
```sql
-- UP
ALTER TABLE posts ALTER COLUMN title DROP NOT NULL;

-- DOWN
ALTER TABLE posts ALTER COLUMN title SET NOT NULL;
```

## Applying Migrations

### Apply All Pending

```bash
aim db:migrate
```

### Apply Up to Specific Migration

```bash
aim db:migrate --target 20250121_110000_add_posts_table
```

### How It Works

1. Checks `_aim_migrations` table for applied migrations
2. Finds pending migrations (not yet applied)
3. Executes each migration's UP section in one transaction, together with
   the record of having applied it, so a statement that fails leaves the
   database as it was
4. Records migration in `_aim_migrations` with:
   - Filename
   - Checksum (to detect modifications)
   - Applied timestamp

### Statements a Transaction Forbids

A few statements cannot run inside a transaction block — `CREATE INDEX
CONCURRENTLY`, `DROP INDEX CONCURRENTLY`, `REINDEX CONCURRENTLY` and
`VACUUM` among them. Put this line in the migration file to run that
migration's statements one at a time instead:

```sql
-- aim: no-transaction
CREATE INDEX CONCURRENTLY idx_posts_slug ON posts (slug);
```

The line may sit anywhere in the file and covers the whole of it, so the
DOWN section runs the same way when `aim db:rollback` reaches it. It applies
only to the migration whose file carries it.

The cost is that a failure part way through leaves the statements before it
applied, and both commands say so when they stop. A statement the database
refuses for this reason is told which line to add.

### Migration Table

Aim automatically creates and manages the `_aim_migrations` table:

```sql
CREATE TABLE _aim_migrations (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL UNIQUE,
  checksum VARCHAR(64) NOT NULL,
  applied_at TIMESTAMP NOT NULL DEFAULT NOW()
);
```

## Rolling Back Migrations

### Rollback Last Migration

```bash
aim db:rollback
```

### Rollback Multiple Migrations

```bash
aim db:rollback --step 3
```

### Rollback to Specific Migration

```bash
aim db:rollback --target 20250121_100000_initial
```

### How It Works

1. Finds the most recently applied migration(s)
2. Prints any comments sitting above the statements — the generated DOWN
   section uses them to say where structure comes back without the rows
   that were in it
3. Executes the DOWN section of each migration and removes the record from
   `_aim_migrations`, both in one transaction

::: warning
A migration whose DOWN section has nothing to run — it is missing, or it
holds only comments — cannot be rolled back automatically. `aim db:rollback`
asks whether to drop it from the history without touching the schema, and
stops if the answer is no.
:::

## Checking Migration Status

```bash
aim db:status
```

Output:
```
Migration Status:

  [✓] 20250121_100000_initial           Applied: 2025-01-21 10:00:00
  [✓] 20250121_110000_add_posts_table   Applied: 2025-01-21 11:00:00
  [ ] 20250121_120000_add_indexes       Pending

Applied: 2 / Total: 3
```

## Best Practices

### 1. Review Generated SQL

Always review the generated migration before applying:

```bash
aim db:generate --name add_feature
cat db/migrations/20250121_*_add_feature.sql
aim db:migrate
```

### 2. Test Migrations Locally

```bash
# Apply
aim db:migrate

# Test your application

# If issues, rollback
aim db:rollback
```

### 3. Commit Migration Files

Migration files should be committed to version control:

```bash
git add db/migrations/
git commit -m "Add posts table migration"
```

### 4. Handle Dangerous Operations

`aim db:generate` warns about potentially dangerous operations:

```
⚠️  Warning: Adding NOT NULL column 'status' without default value.
    This will fail if the table contains existing rows.
    Consider adding a default value: .withDefault('pending')
```

### 5. Use Transactions

Migrations run within a transaction by default. If a migration fails:
- All changes are rolled back
- The migration is not recorded as applied
- You can fix the issue and retry

A migration carrying the `-- aim: no-transaction` line is the exception, and
gives this up for the statements that need it.

## Workflow Example

### Initial Setup

```bash
# Create schema
vim lib/schema.dart

# Generate initial migration
aim db:generate --name initial

# Review
cat db/migrations/*_initial.sql

# Apply
aim db:migrate
```

### Adding a Feature

```bash
# Update schema
vim lib/schema.dart

# Regenerate code
dart run build_runner build

# Generate migration
aim db:generate --name add_comments

# Review and apply
aim db:migrate
```

### Handling Mistakes

```bash
# Oops, wrong migration
aim db:rollback

# Fix schema
vim lib/schema.dart

# Regenerate
dart run build_runner build
aim db:generate --name add_comments_fixed

# Apply correct migration
aim db:migrate
```

## Limitations

The following features are not yet supported:

| Feature | Status |
|---------|--------|
| `db:reset` | Planned |
| RENAME TABLE | Not supported |
| Composite indexes | Not supported |
| Composite unique constraints | Not supported |
| CHECK constraints | Not supported |
| ENUM types | Not supported |

## Next Steps

- [Schema Definition](/database/orm/schema) - Column types and modifiers
- [CLI Commands](/cli/commands#database-commands) - Full command reference
