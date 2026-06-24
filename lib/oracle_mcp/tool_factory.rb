# frozen_string_literal: true

require "json"
require "mcp"

require_relative "client"

module OracleMcp
  # Turns a compact tool spec into an MCP::Tool.
  #
  # Every tool maps 1:1 to an {OracleMcp::Client} method of the same name, so a
  # single handler forwards the validated arguments straight through. Parameter
  # defaults therefore live in one place: the client method signature.
  module ToolFactory
    module_function

    # Build an MCP::Tool.
    #
    # @param name [String] tool name; must match a Client method.
    # @param description [String] human/LLM-facing description.
    # @param properties [Hash] JSON Schema properties for each argument.
    # @param required [Array<String>] names of required arguments.
    # @param read_only [Boolean] true for tools that only read data.
    # @param destructive [Boolean] true for tools that can modify or delete data.
    # @param idempotent [Boolean] true when repeating the call has no extra effect.
    def build(name:, description:, properties: {}, required: [], read_only: false, destructive: false,
              idempotent: false)
      schema = { properties: properties }
      schema[:required] = required unless required.empty?
      annotations = {
        read_only_hint: read_only,
        destructive_hint: destructive,
        idempotent_hint: idempotent,
      }

      MCP::Tool.define(
        name: name,
        description: description,
        input_schema: schema,
        annotations: annotations,
      ) do |**args|
        args.delete(:server_context)
        ToolFactory.invoke(name, args)
      end
    end

    # Dispatch a validated tool call to the matching client method and wrap the
    # result as an MCP tool response. Known failures (bad SQL, read-only
    # violations, missing config) become a clean tool error rather than a
    # transport-level crash.
    def invoke(name, args)
      result = dispatch(name, args)
      text = result.is_a?(String) ? result : JSON.pretty_generate(result)
      MCP::Tool::Response.new([{ type: "text", text: text }])
    rescue OracleMcp::Error => e
      MCP::Tool::Response.new([{ type: "text", text: e.message }], error: true)
    end

    # Call the memoized client. If the connection dropped, reset and try once
    # more on a fresh connection.
    def dispatch(name, args)
      OracleMcp.client.public_send(name, **args)
    rescue OracleMcp::ConnectionError
      OracleMcp.reset_client!
      OracleMcp.client.public_send(name, **args)
    end
  end
end
