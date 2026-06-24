# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < Test::Unit::TestCase
  include TestHelpers

  # ----- configuration -----

  test "reads credentials from the environment" do
    with_env("ORACLE_USER" => "scott", "ORACLE_PASSWORD" => "tiger", "ORACLE_DSN" => "db:1521/orcl") do
      client = OracleMcp::Client.new
      assert_equal("scott", client.user)
      assert_equal("db:1521/orcl", client.dsn)
      assert_false(client.read_only?)
    end
  end

  test "raises when required credentials are missing" do
    with_env("ORACLE_USER" => nil, "ORACLE_PASSWORD" => nil, "ORACLE_DSN" => nil) do
      assert_raise(OracleMcp::ConfigurationError) { OracleMcp::Client.new }
    end
  end

  test "rejects a non-numeric ORACLE_MCP_MAX_ROWS" do
    with_env("ORACLE_USER" => "u", "ORACLE_PASSWORD" => "p", "ORACLE_DSN" => "d", "ORACLE_MCP_MAX_ROWS" => "lots") do
      assert_raise(OracleMcp::ConfigurationError) { OracleMcp::Client.new }
    end
  end

  test "honors ORACLE_MCP_READ_ONLY" do
    with_env("ORACLE_USER" => "u", "ORACLE_PASSWORD" => "p", "ORACLE_DSN" => "d", "ORACLE_MCP_READ_ONLY" => "true") do
      assert_true(OracleMcp::Client.new.read_only?)
    end
  end

  # ----- select -----

  test "select returns a structured, coerced result set" do
    conn = fake_connection(columns: [col("ID", :number), col("NAME", :varchar2)], rows: [[1, "Ann"], [2, "Bob"]])
    result = build_client(connection: conn).send(:select, "SELECT id, name FROM people")

    assert_equal([{ "name" => "ID", "type" => "number" }, { "name" => "NAME", "type" => "varchar2" }],
                 result["columns"])
    assert_equal([[1, "Ann"], [2, "Bob"]], result["rows"])
    assert_equal(2, result["row_count"])
    assert_false(result["truncated"])
    assert_equal("SELECT id, name FROM people", conn.parsed.last)
  end

  test "select caps rows at max_rows and flags truncation" do
    conn = fake_connection(columns: [col("N", :number)], rows: [[1], [2], [3], [4]])
    result = build_client(connection: conn, max_rows: 2).send(:select, "SELECT n FROM t")

    assert_equal([[1], [2]], result["rows"])
    assert_equal(2, result["row_count"])
    assert_true(result["truncated"])
  end

  test "select binds named parameters" do
    conn = fake_connection
    build_client(connection: conn).send(:select, "SELECT * FROM t WHERE id = :id AND k = :k", binds: { id: 7, "k" => "x" })
    assert_equal({ ":id" => 7, ":k" => "x" }, conn.last_cursor.binds)
  end

  test "select binds positional parameters from an array" do
    conn = fake_connection
    build_client(connection: conn).send(:select, "SELECT * FROM t WHERE a = :1 AND b = :2", binds: [10, 20])
    assert_equal({ 1 => 10, 2 => 20 }, conn.last_cursor.binds)
  end

  # ----- read-only safety -----

  test "read-only select rejects non-select statements" do
    client = build_client(read_only: true)
    assert_raise(OracleMcp::StatementNotAllowedError) { client.send(:select, "DELETE FROM t") }
    assert_raise(OracleMcp::StatementNotAllowedError) { client.send(:select, "BEGIN do_it; END;") }
  end

  test "read-only select rejects multiple statements" do
    client = build_client(read_only: true)
    assert_raise(OracleMcp::StatementNotAllowedError) { client.send(:select, "SELECT 1 FROM dual; SELECT 2 FROM dual") }
  end

  test "read-only select allows SELECT and WITH (ignoring comments and a trailing semicolon)" do
    conn = fake_connection(columns: [col("X", :number)], rows: [[1]])
    client = build_client(connection: conn, read_only: true)
    assert_nothing_raised do
      client.send(:select, "-- a comment\nSELECT x FROM t;")
      client.send(:select, "WITH q AS (SELECT 1 x FROM dual) SELECT * FROM q")
    end
  end

  # ----- execute -----

  test "execute reports affected rows for DML" do
    conn = fake_connection(row_count: 3)
    result = build_client(connection: conn).send(:execute, "UPDATE t SET x = 1")
    assert_equal({ "rows_affected" => 3 }, result)
  end

  test "execute reports status for DDL" do
    conn = fake_connection
    result = build_client(connection: conn).send(:execute, "CREATE TABLE t (id NUMBER)")
    assert_equal({ "status" => "ok" }, result)
  end

  test "execute is refused in read-only mode" do
    assert_raise(OracleMcp::ReadOnlyError) { build_client(read_only: true).send(:execute, "DELETE FROM t") }
  end

  # ----- coercion -----

  test "coerce maps Oracle values to JSON-friendly Ruby" do
    client = build_client

    assert_nil(client.send(:coerce, nil))
    assert_equal(42, client.send(:coerce, 42))
    assert_equal(3.5, client.send(:coerce, 3.5))
    assert_equal(10, client.send(:coerce, BigDecimal("10")))
    assert_equal(1.5, client.send(:coerce, BigDecimal("1.5")))
    assert_equal("2026-06-24T08:30:00+00:00", client.send(:coerce, Time.utc(2026, 6, 24, 8, 30, 0).getlocal("+00:00")))
    assert_equal("2026-06-24", client.send(:coerce, Date.new(2026, 6, 24)))
    assert_equal("hello", client.send(:coerce, "hello"))
  end

  test "coerce base64-encodes binary RAW strings" do
    raw = [0xDE, 0xAD, 0xBE, 0xEF].pack("C*")
    result = build_client.send(:coerce, raw)
    assert_equal("raw", result["type"])
    assert_equal(raw, Base64.strict_decode64(result["base64"]))
  end

  test "coerce reads CLOBs as text and BLOBs as base64" do
    client = build_client
    assert_equal("clob text", client.send(:coerce, FakeClob.new("clob text")))

    blob = client.send(:coerce, FakeBlob.new("\x00\x01\x02"))
    assert_equal("blob", blob["type"])
    assert_equal("\x00\x01\x02".b, Base64.strict_decode64(blob["base64"]))
  end

  test "coerce truncates oversized CLOBs" do
    result = build_client(max_lob_bytes: 4).send(:coerce, FakeClob.new("abcdefgh"))
    assert_equal("abcd… [truncated]", result)
  end

  # ----- error handling + reconnect -----

  test "maps an Oracle error to QueryError" do
    conn = fake_connection.fail_execs_with(oci_error("ORA-00942: table or view does not exist", 942))
    error = assert_raise(OracleMcp::QueryError) { build_client(connection: conn).send(:select, "SELECT 1 FROM missing") }
    assert_match(/ORA-00942/, error.message)
  end

  test "reconnects once after a dropped connection, then succeeds" do
    conn = fake_connection.fail_execs_with(oci_error("ORA-03113: end-of-file on communication channel", 3113))
    result = build_client(connection: conn).send(:select, "SELECT 1 FROM dual")
    assert_kind_of(Hash, result)
    assert_equal(1, conn.logoff_count)
    assert_equal(2, conn.parsed.length)
  end

  test "raises ConnectionError when the connection stays dead" do
    dead = oci_error("ORA-03114: not connected to ORACLE", 3114)
    conn = fake_connection.fail_execs_with(dead, dead)
    assert_raise(OracleMcp::ConnectionError) { build_client(connection: conn).send(:select, "SELECT 1 FROM dual") }
  end

  # ----- timeout -----

  test "enforces a best-effort query timeout" do
    conn = fake_connection.sleep_on_exec(0.2)
    error = assert_raise(OracleMcp::QueryError) do
      build_client(connection: conn, query_timeout: 0.05).send(:select, "SELECT 1 FROM dual")
    end
    assert_match(/timeout/i, error.message)
    assert_true(conn.broken?)
  end

  # ----- close -----

  test "close logs off the connection" do
    conn = fake_connection
    client = build_client(connection: conn)
    client.send(:select, "SELECT 1 FROM dual")
    client.close
    assert_equal(1, conn.logoff_count)
  end
end
