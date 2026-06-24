# frozen_string_literal: true

require_relative "test_helper"

class ServerTest < Test::Unit::TestCase
  include TestHelpers

  def setup
    OracleMcp.reset_client!
  end

  def teardown
    OracleMcp.reset_client!
  end

  def tools
    OracleMcp::Tools.all
  end

  def find_tool(name)
    tools.find { |tool| tool.name_value == name } or raise "tool #{name} not registered"
  end

  # Point the memoized client at a fake connection for dispatch tests.
  def use_connection(connection, **opts)
    OracleMcp.client = build_client(connection: connection, **opts)
  end

  # ----- .build -----

  test ".build builds an MCP server named oracle_mcp with every tool" do
    server = OracleMcp::Server.build
    assert_kind_of(MCP::Server, server)
    assert_equal("oracle_mcp", server.name)
    assert_equal(OracleMcp::VERSION, server.version)
    assert_equal(tools.size, server.tools.size)
  end

  # ----- tool registry -----

  test "registers a meaningful set of tools" do
    assert_operator(tools.size, :>=, 20)
  end

  test "gives every tool a unique name" do
    names = tools.map(&:name_value)
    assert_equal(names.length, names.uniq.length)
  end

  test "maps every tool to a client method of the same name" do
    client = build_client
    tools.each { |tool| assert_respond_to(client, tool.name_value) }
  end

  test "produces a valid JSON Schema for every tool" do
    tools.each do |tool|
      schema = tool.input_schema.to_h
      assert_equal("object", schema[:type])
      assert(schema.key?(:properties), "expected #{tool.name_value} schema to declare :properties")
    end
  end

  test "annotates read-only and destructive tools" do
    assert_true(find_tool("get_database_info").annotations_value.read_only_hint)
    assert_true(find_tool("list_tables").annotations_value.read_only_hint)
    assert_true(find_tool("execute_statement").annotations_value.destructive_hint)
    assert_true(find_tool("execute_plsql").annotations_value.destructive_hint)
    assert_false(find_tool("execute_statement").annotations_value.read_only_hint)
  end

  test "accepts binds as either an object or an array during validation" do
    schema = find_tool("execute_query").input_schema
    assert_nothing_raised do
      schema.validate_arguments("sql" => "SELECT 1 FROM dual", "binds" => { "id" => 1 })
      schema.validate_arguments("sql" => "SELECT 1 FROM dual", "binds" => [1, 2])
    end
  end

  # ----- tool dispatch -----

  test "forwards arguments to the client and returns JSON text" do
    use_connection(fake_connection(columns: [col("N", :number)], rows: [[1]]))
    response = find_tool("execute_query").call(sql: "SELECT n FROM t")
    assert_kind_of(MCP::Tool::Response, response)
    assert_false(response.error?)
    assert_equal([[1]], JSON.parse(response.content.first[:text])["rows"])
  end

  test "passes string results through without JSON-encoding" do
    use_connection(fake_connection(columns: [col("DDL", :clob)], rows: [["CREATE TABLE EMP (...)"]]))
    response = find_tool("get_object_ddl").call(object_type: "table", name: "emp")
    assert_equal("CREATE TABLE EMP (...)", response.content.first[:text])
  end

  test "ignores an injected server_context argument" do
    use_connection(fake_connection)
    response = find_tool("ping").call(server_context: :ignored)
    assert_false(response.error?)
  end

  test "turns Oracle failures into a tool error response" do
    use_connection(fake_connection.fail_execs_with(oci_error("ORA-00942: table or view does not exist", 942)))
    response = find_tool("execute_query").call(sql: "SELECT 1 FROM missing")
    assert_true(response.error?)
    assert_match(/ORA-00942/, response.content.first[:text])
  end

  test "turns a read-only violation into a tool error response" do
    use_connection(fake_connection, read_only: true)
    response = find_tool("execute_statement").call(sql: "DELETE FROM t")
    assert_true(response.error?)
    assert_match(/ORACLE_MCP_READ_ONLY/, response.content.first[:text])
  end

  test "turns missing credentials into a tool error response" do
    with_env("ORACLE_USER" => nil, "ORACLE_PASSWORD" => nil, "ORACLE_DSN" => nil) do
      response = find_tool("ping").call
      assert_true(response.error?)
      assert_match(/ORACLE_USER/, response.content.first[:text])
    end
  end

  # ----- end-to-end through the MCP server -----

  test "answers a tools/call JSON-RPC request" do
    use_connection(fake_connection)
    request = {
      jsonrpc: "2.0", id: 1, method: "tools/call",
      params: { name: "ping", arguments: {} }
    }
    response = JSON.parse(OracleMcp::Server.build.handle_json(JSON.generate(request)))
    assert_false(response.dig("result", "isError"))
    assert_equal({ "ok" => true }, JSON.parse(response.dig("result", "content", 0, "text")))
  end

  test "lists tools over JSON-RPC" do
    request = { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }
    response = JSON.parse(OracleMcp::Server.build.handle_json(JSON.generate(request)))
    names = response.dig("result", "tools").map { |tool| tool["name"] }
    assert_include(names, "execute_query")
    assert_include(names, "list_tables")
  end

  # ----- .run CLI -----

  test ".run prints the version" do
    assert_equal("#{OracleMcp::VERSION}\n", capture_stdout { OracleMcp::Server.run(["--version"]) })
  end

  test ".run prints usage help" do
    assert_match(/MCP server for Oracle Database/, capture_stdout { OracleMcp::Server.run(["--help"]) })
  end
end
