# oracle_mcp

A [Model Context Protocol](https://modelcontextprotocol.io) (MCP) server that exposes an
**Oracle Database** to any MCP-compatible client (Claude Code, Claude Desktop, Cursor, Cline,
Zed, custom agents). It lets an agent run SQL, inspect schema, generate DDL, and monitor the
instance — over stdio.

It connects to Oracle through [ruby-oci8](https://github.com/kubo/ruby-oci8). The server
itself is pure Ruby with minimal runtime dependencies (the MCP SDK and `dotenv`).

> [!WARNING]
> **Writes are enabled by default.** The server can run `INSERT`/`UPDATE`/`DELETE`/`MERGE`,
> DDL, and PL/SQL out of the box. Set `ORACLE_MCP_READ_ONLY=true` to refuse all writes, and
> connect with a **least-privilege database account** — that account's grants are the real
> security boundary. See [Security](#security).

## Tools

26 tools across seven areas. All are read-only unless marked.

| Area | Tools |
|---|---|
| Query | `execute_query`, `explain_plan`, `execute_statement` ⚠️, `execute_plsql` ⚠️ |
| Schema | `list_schemas`, `list_tables`, `list_views`, `describe_table`, `count_table_rows`, `sample_table` |
| Structure | `list_indexes`, `list_constraints`, `list_foreign_keys`, `list_sequences` |
| Routines | `list_procedures`, `list_functions`, `list_packages`, `list_objects`, `get_object_ddl` |
| Database | `get_database_info`, `ping` |
| Monitoring (DBA) | `list_sessions`, `list_blocking_sessions`, `instance_stats`, `list_parameters`, `tablespace_usage` |

⚠️ = write tool (refused when `ORACLE_MCP_READ_ONLY=true`). Monitoring tools read `V$`/`DBA_*`
views and need elevated `SELECT` (e.g. `SELECT_CATALOG_ROLE`).

## Prerequisites

- **Ruby** >= 3.1.
- **Oracle Instant Client** (`Basic` **and** `SDK` packages) — required by `ruby-oci8` to
  build and to connect.
  - macOS Apple Silicon (M-series) is supported:
    [Instant Client for macOS (ARM64)](https://www.oracle.com/database/technologies/instant-client/macos-arm64-downloads.html).
    (ruby-oci8's own install page is out of date and still says ARM64 is unavailable — ignore it.)
  - Linux/Windows downloads are linked from the same Instant Client site.
  - Point `ruby-oci8` at the client by setting `OCI_DIR` (and adding the client to your
    library path, e.g. `DYLD_LIBRARY_PATH` on macOS, `LD_LIBRARY_PATH` on Linux).
- **ruby-oci8** — installed via the optional Bundler group below, or `gem install ruby-oci8`.

## Installation

```sh
git clone https://github.com/kaiquekandykoga/oracle_mcp.git
cd oracle_mcp

# Default install — pure Ruby, no Oracle client needed (this is all CI runs).
bundle install

# To make real Oracle connections, install Instant Client (above), then add ruby-oci8:
bundle config set --local with oracle
bundle install
```

`ruby-oci8` lives in an **optional** Bundler group so the project installs and its full test
suite runs anywhere — the tests use a fake connection and never touch a database. You only
need Instant Client + `ruby-oci8` to connect for real.

## Configuration

Credentials and tuning come from the environment (a local `.env` file is loaded automatically
when present):

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `ORACLE_USER` | ✓ | — | Database username |
| `ORACLE_PASSWORD` | ✓ | — | Database password |
| `ORACLE_DSN` | ✓ | — | Easy Connect string (`host:port/service`) or a TNS alias |
| `ORACLE_PRIVILEGE` | | — | Connection privilege: `SYSDBA`, `SYSOPER`, … |
| `ORACLE_MCP_READ_ONLY` | | `false` | `true` refuses all writes |
| `ORACLE_MCP_MAX_ROWS` | | `1000` | Max rows returned per query |
| `ORACLE_MCP_MAX_LOB_BYTES` | | `1000000` | Cap on CLOB/BLOB bytes returned |
| `ORACLE_MCP_QUERY_TIMEOUT` | | — | Best-effort per-statement timeout, in seconds |
| `TNS_ADMIN` | | — | Directory with `tnsnames.ora` / a wallet (read natively by OCI8) |

## Using it with an MCP client

Add the server to your client's MCP configuration (for the Claude CLI this is `~/.claude.json`):

```json
{
  "mcpServers": {
    "oracle_mcp": {
      "command": "bundle",
      "args": ["exec", "oracle-mcp"],
      "env": {
        "ORACLE_USER": "scott",
        "ORACLE_PASSWORD": "tiger",
        "ORACLE_DSN": "db.example.com:1521/ORCLPDB1",
        "ORACLE_MCP_READ_ONLY": "true"
      }
    }
  }
}
```

Run `bundle exec oracle-mcp` from the project directory (so Bundler finds `ruby-oci8`). If you
install the gem and `ruby-oci8` system-wide, use `"command": "oracle-mcp"` with no `args`.

You can also drive the server by hand with the official inspector:

```sh
npx @modelcontextprotocol/inspector bundle exec oracle-mcp
```

## Security

- **Least privilege is the real boundary.** Create a dedicated Oracle account granted only what
  the agent should touch. App-level guards are convenience, not a substitute for grants.
- **Read-only mode:** `ORACLE_MCP_READ_ONLY=true` refuses every write tool and restricts
  `execute_query` to a single `SELECT`/`WITH` statement (no multiple statements, no PL/SQL).
- **Always prefer bind variables.** Every built-in introspection query is parameterized;
  pass `binds` to `execute_query`/`execute_statement` rather than interpolating values.
- **Result limits** (`ORACLE_MCP_MAX_ROWS`, `ORACLE_MCP_MAX_LOB_BYTES`) keep large results from
  overwhelming the client; responses flag `"truncated": true` when more was available.
- Monitoring tools require elevated `SELECT` on `V$`/`DBA_*` views; grant them only if you want
  those tools to work.

## Development

```sh
bundle install                 # pure-Ruby deps; no Oracle client required
bundle exec rake               # tests + RuboCop (the default task)
bundle exec rake test          # tests only
bundle exec rubocop            # lint only
bundle exec bin/oracle-mcp --help
```

The suite is **hermetic**: a fake OCI8 connection records the SQL and binds each method
produces, so no Oracle instance or Instant Client is needed to develop or to run CI.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
