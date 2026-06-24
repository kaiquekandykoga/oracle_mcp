# frozen_string_literal: true

require_relative "../test_helper"

class QueryOperationsTest < Test::Unit::TestCase
  include TestHelpers

  test "execute_query forwards SQL, binds and limit to the query path" do
    conn = fake_connection(columns: [col("X", :number)], rows: [[1], [2]])
    result = build_client(connection: conn).execute_query(sql: "SELECT x FROM t WHERE id = :id", binds: { id: 5 }, limit: 1)

    assert_equal("SELECT x FROM t WHERE id = :id", conn.parsed.last)
    assert_equal({ ":id" => 5 }, conn.last_cursor.binds)
    assert_equal([[1]], result["rows"])
    assert_true(result["truncated"])
  end

  test "execute_query rejects non-SELECT statements even when writes are enabled" do
    client = build_client(read_only: false)
    assert_raise(OracleMcp::StatementNotAllowedError) { client.execute_query(sql: "DELETE FROM t") }
    assert_raise(OracleMcp::StatementNotAllowedError) { client.execute_query(sql: "UPDATE t SET x = 1") }
  end

  test "execute_statement runs DML and reports affected rows" do
    conn = fake_connection(row_count: 2)
    result = build_client(connection: conn).execute_statement(sql: "UPDATE t SET x = 1 WHERE id = :id", binds: { id: 5 })

    assert_equal("UPDATE t SET x = 1 WHERE id = :id", conn.parsed.last)
    assert_equal({ ":id" => 5 }, conn.last_cursor.binds)
    assert_equal({ "rows_affected" => 2 }, result)
  end

  test "execute_statement is refused in read-only mode" do
    assert_raise(OracleMcp::ReadOnlyError) do
      build_client(read_only: true).execute_statement(sql: "DELETE FROM t")
    end
  end

  test "execute_plsql runs an anonymous block" do
    conn = fake_connection
    result = build_client(connection: conn).execute_plsql(plsql: "BEGIN do_it; END;")

    assert_equal("BEGIN do_it; END;", conn.parsed.last)
    assert_equal({ "status" => "ok" }, result)
  end

  test "explain_plan explains then displays the plan as text" do
    conn = fake_connection(columns: [col("PLAN_TABLE_OUTPUT")], rows: [["Plan step 1"], ["Plan step 2"]])
    result = build_client(connection: conn).explain_plan(sql: "SELECT * FROM t")

    assert_equal("EXPLAIN PLAN FOR SELECT * FROM t", conn.parsed[0])
    assert_match(/DBMS_XPLAN.DISPLAY/, parsed_sql(conn, 1))
    assert_equal("Plan step 1\nPlan step 2", result)
  end
end
