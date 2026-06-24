# AGENTS.md

`CLAUDE.md` is a symlink to this file — one source of truth; edit `AGENTS.md`, never duplicate it.

`oracle_mcp` is a Ruby gem: a Model Context Protocol (MCP) server that exposes an Oracle
Database as 26 tools, runnable by any MCP client over stdio. Runtime dependencies are minimal
(`mcp`, `dotenv`, `base64`); the database driver is `ruby-oci8`, kept in an optional Bundler
group so the project builds and tests without Oracle installed.

## Commands

```sh
bundle install                                            # pure-Ruby deps (no Oracle client)
bundle config set --local with oracle && bundle install  # add ruby-oci8 for real connections

bundle exec rake                                          # default: tests + RuboCop
bundle exec rake test                                     # whole test suite
bundle exec ruby -Itest test/operations/tables_test.rb    # one test file
bundle exec ruby -Itest test/operations/tables_test.rb -n "/sample/"  # tests matching a pattern

bundle exec rubocop                                      # lint
bundle exec rubocop -a                                   # lint + safe autocorrect

bundle exec bin/oracle-mcp --version                     # CLI (also --help)
npx @modelcontextprotocol/inspector bundle exec oracle-mcp  # drive the server by hand
```

Tests are **hermetic**: they inject a fake OCI8 connection (`test/test_helper.rb`), so no
Oracle instance or Instant Client is needed. `Gemfile.lock` is not committed (CI resolves
fresh per Ruby version). CI lints on Ruby 4.0 and tests on Ruby 4.0 and 3.4.

## Architecture

Four layers, wired together by a single naming convention.

**1. `Client` + `Operations` (the OCI8 layer).** `lib/oracle_mcp/client.rb` is a thin
ruby-oci8 client. It `include`s every module under `OracleMcp::Operations` (auto-discovered via
`Operations.constants`). Each `lib/oracle_mcp/operations/<area>.rb` defines plain instance
methods (e.g. `list_tables(owner:, name_like:)`) that only build SQL + binds and delegate to the
private `select` (queries) or `execute` (writes). All OCI8 concerns live in those two methods
and their helpers — operation methods never touch OCI8.

Things the core handles that operations rely on:
- **`select(sql, binds:, limit:)`** parses, binds, executes, and fetches up to
  `limit`/`ORACLE_MCP_MAX_ROWS` rows, returning
  `{ "columns" => [...], "rows" => [...], "row_count" => n, "truncated" => bool }`.
- **`execute(sql, binds:)`** runs DML/DDL/PL-SQL, returning `{ "rows_affected" => n }` (DML) or
  `{ "status" => "ok" }`. Raises `ReadOnlyError` when `ORACLE_MCP_READ_ONLY` is set.
- **Binds:** a Hash binds by name (`:name`), an Array by 1-based position.
- **Coercion** (`coerce`): NUMBER → Integer/Float; DATE/TIMESTAMP → ISO-8601; CLOB → text
  (capped); BLOB/RAW → base64 (capped); everything JSON-friendly. Duck-typed so this file
  references no OCI8 constants (which keeps tests OCI8-free).
- **Read-only safety** (`assert_read_safe`): in read-only mode, `select` allows only a single
  `SELECT`/`WITH` (no multiple statements, no PL/SQL).
- **Identifier safety** (`quote_ident`/`qualified_name`): the few tools that must name a table
  in SQL text (`count_table_rows`, `sample_table`) validate and double-quote it; everything else
  uses binds.
- **Connection + errors:** the connection is opened lazily (`require "oci8"` happens here, not
  at load time) and reused. A dropped connection (known ORA codes) is reconnected and retried
  once, then surfaces as `ConnectionError`; other Oracle errors become `QueryError`. All
  library errors descend from `OracleMcp::Error` (`errors.rb`).

**2. `Tools` + `ToolFactory` + `Schema` (the MCP tool layer).** Each
`lib/oracle_mcp/tools/<area>.rb` mirrors the matching `operations/<area>.rb` and exposes `.all`,
an array of `ToolFactory.build(...)` results. `Schema` (`schema.rb`) provides JSON-Schema
fragment helpers (`str`, `int`, `bool`, `strs`, `array`, `object`, `any`) plus shared
`OWNER`/`OBJECT_NAME`/`NAME_LIKE`/`BINDS`/`LIMIT` constants. `Tools.all` aggregates every
category, sorted by name.

**3. `Server` (the runtime).** `server.rb` builds an `MCP::Server` from `Tools.all` and serves
it over stdio; the CLI (`bin/oracle-mcp`) handles `--version`/`--help`, loads `.env` (via
optional `dotenv`), and opens the transport.

**The central invariant: each tool's `name` must equal a `Client` method of the same name.**
`ToolFactory.invoke` dispatches every call with `OracleMcp.client.public_send(name, **args)`.
Consequences:
- Adding a capability = add a method in `operations/<area>.rb` **and** a
  `ToolFactory.build(name: "<same_name>", ...)` in the paired `tools/<area>.rb`, with property
  names matching the method's keyword args. Classify it: `read_only: true` for reads,
  `destructive: true` for writes (DML/DDL/PL-SQL).
- Parameter **defaults live only in the operation method signature** — tool schemas declare
  types and `required:`, not defaults.
- `test/server_test.rb` enforces the 1:1 mapping, schema validity, and annotation correctness —
  run it after touching tools or operations.

**Memoized client (a deliberate difference from a stateless HTTP MCP server).** A database
connection is expensive, so `OracleMcp.client` memoizes one `Client` (one OCI8 connection,
opened lazily) and reuses it across tool calls; the stdio transport serves one request at a
time, so no pool is needed. `OracleMcp.reset_client!` drops it (used to recover from a dropped
connection and by tests). Config is read from the environment when the client is built:
`ORACLE_USER`/`ORACLE_PASSWORD`/`ORACLE_DSN` (required), `ORACLE_PRIVILEGE`,
`ORACLE_MCP_READ_ONLY` (default false), `ORACLE_MCP_MAX_ROWS` (1000),
`ORACLE_MCP_MAX_LOB_BYTES` (1_000_000), `ORACLE_MCP_QUERY_TIMEOUT` (best-effort).

### Schema gotcha for free-form params

`binds` may be an object (named) or an array (positional), so it uses `Schema.any` — a fragment
with **no `type`** — and validation accepts either. Don't pin it to `object`/`array`, and for
nested object/array params use `Schema.object`/`Schema.array` (which omit
`additionalProperties`/`items`) so valid input isn't rejected.

## Conventions

- **Tests** use `test-unit` with a hand-rolled fake OCI8 (`FakeOCI8`/`FakeCursor`/`FakeColumn`,
  plus `FakeClob`/`FakeBlob`) — there is no WebMock equivalent for a DB driver. Files live in
  `test/` and `test/operations/` as `<name>_test.rb`. Helpers in `test/test_helper.rb`:
  `build_client`, `fake_connection`, `col`, `oci_error`, `with_env`, `capture_stdout`,
  `normalize_sql`/`parsed_sql`. Operation tests assert the SQL + binds a method produces.
- **RuboCop** (`.rubocop.yml`) is intentionally minimal: most cops disabled, double-quoted
  strings. Keep operation/tool entries in the wide, table-like form the surrounding code uses.
- **SQL** uses the Oracle data dictionary (`ALL_*`) and `V$`/`DBA_*` views. Owner defaults to the
  connected user via `NVL(UPPER(:owner), USER)`; name filters use `UPPER(:name_like)`.
  ruby-oci8 is `require`d lazily, never at file-load time, so the library loads without it.
