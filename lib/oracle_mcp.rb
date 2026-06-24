# frozen_string_literal: true

require_relative "oracle_mcp/version"
require_relative "oracle_mcp/errors"
require_relative "oracle_mcp/client"
require_relative "oracle_mcp/schema"
require_relative "oracle_mcp/tool_factory"
require_relative "oracle_mcp/tools"
require_relative "oracle_mcp/server"

# Top-level namespace for the Oracle MCP server.
#
# - {OracleMcp::Client} talks to an Oracle Database via ruby-oci8.
# - {OracleMcp::Tools} exposes each client method as an MCP tool.
# - {OracleMcp::Server} runs the tools over the Model Context Protocol.
module OracleMcp
  class << self
    # Process-wide memoized client. Unlike a stateless HTTP client, a database
    # connection is expensive to create, so one client (holding a single OCI8
    # connection, opened lazily on first use) is reused across tool calls. The
    # stdio transport serves one request at a time, so no connection pool is
    # needed.
    def client
      @client ||= Client.new
    end

    # Replace the memoized client. Used by tests to inject a fake connection.
    attr_writer :client

    # Drop the memoized client, closing its connection. The next {client} call
    # reconnects. Used to recover from a dropped connection.
    def reset_client!
      @client&.close
    rescue StandardError
      nil
    ensure
      @client = nil
    end
  end
end
