# frozen_string_literal: true

require "mcp"

require_relative "version"
require_relative "tools"

module OracleMcp
  # Builds and runs the Oracle MCP server over stdio.
  module Server
    module_function

    SERVER_NAME = "oracle_mcp"

    USAGE = <<~TEXT
      oracle-mcp - MCP server for Oracle Database (via ruby-oci8)

      Usage: oracle-mcp [options]

      The server speaks the Model Context Protocol over stdio. It is normally
      launched by an MCP client (Claude, an editor, an agent), not run directly.

      Options:
        -v, --version   Print the version and exit.
        -h, --help      Print this help and exit.

      Required environment variables:
        ORACLE_USER       Database username.
        ORACLE_PASSWORD   Database password.
        ORACLE_DSN        Easy Connect string (host:port/service) or TNS alias.

      Optional environment variables:
        ORACLE_PRIVILEGE        Connection privilege (SYSDBA, SYSOPER, ...).
        ORACLE_MCP_READ_ONLY    Set to true to refuse all writes (default false).
        ORACLE_MCP_MAX_ROWS     Max rows returned per query (default 1000).
        ORACLE_MCP_MAX_LOB_BYTES  Cap on CLOB/BLOB bytes returned (default 1000000).
        ORACLE_MCP_QUERY_TIMEOUT  Best-effort per-statement timeout, in seconds.
        TNS_ADMIN               Directory holding tnsnames.ora / a wallet (native OCI8).

      WARNING: writes are ENABLED by default. Set ORACLE_MCP_READ_ONLY=true and/or
      connect with a least-privilege account to restrict what the server can do.
    TEXT

    # Build the underlying MCP::Server with every Oracle tool registered.
    def build
      MCP::Server.new(
        name: SERVER_NAME,
        version: OracleMcp::VERSION,
        tools: OracleMcp::Tools.all,
      )
    end

    # Entry point for the executable. Handles --version/--help, then serves stdio.
    def run(argv = ARGV)
      case argv[0]
      when "-v", "--version"
        puts OracleMcp::VERSION
        return
      when "-h", "--help"
        puts USAGE
        return
      end

      load_dotenv
      MCP::Server::Transports::StdioTransport.new(build).open
    end

    # Load a local .env file when the optional `dotenv` gem is available. The
    # server also works with credentials injected directly into the environment.
    def load_dotenv
      require "dotenv"
      Dotenv.load
    rescue LoadError
      nil
    end
  end
end
