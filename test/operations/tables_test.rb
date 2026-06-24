# frozen_string_literal: true

require_relative "../test_helper"

class TablesOperationsTest < Test::Unit::TestCase
  include TestHelpers

  def client(conn)
    build_client(connection: conn)
  end

  test "list_schemas queries all_users, optionally filtered" do
    conn = fake_connection
    client(conn).list_schemas
    assert_match(/FROM all_users ORDER BY username/, parsed_sql(conn))
    assert_equal({}, conn.last_cursor.binds)

    client(conn).list_schemas(name_like: "A%")
    assert_match(/WHERE username LIKE UPPER\(:name_like\)/, parsed_sql(conn))
    assert_equal({ ":name_like" => "A%" }, conn.last_cursor.binds)
  end

  test "list_tables defaults owner to the current user" do
    conn = fake_connection
    client(conn).list_tables
    assert_match(/FROM all_tables WHERE owner = NVL\(UPPER\(:owner\), USER\)/, parsed_sql(conn))
    assert_equal({ ":owner" => nil }, conn.last_cursor.binds)

    client(conn).list_tables(owner: "scott", name_like: "EMP%")
    assert_match(/AND table_name LIKE UPPER\(:name_like\)/, parsed_sql(conn))
    assert_equal({ ":owner" => "scott", ":name_like" => "EMP%" }, conn.last_cursor.binds)
  end

  test "list_views queries all_views" do
    conn = fake_connection
    client(conn).list_views(owner: "scott")
    assert_match(/FROM all_views WHERE owner = NVL\(UPPER\(:owner\), USER\)/, parsed_sql(conn))
    assert_equal({ ":owner" => "scott" }, conn.last_cursor.binds)
  end

  test "describe_table joins columns with comments" do
    conn = fake_connection
    client(conn).describe_table(table: "emp")
    sql = parsed_sql(conn)
    assert_match(/FROM all_tab_columns c/, sql)
    assert_match(/all_col_comments cc/, sql)
    assert_match(/c.table_name = UPPER\(:table_name\)/, sql)
    assert_equal({ ":owner" => nil, ":table_name" => "emp" }, conn.last_cursor.binds)
  end

  test "count_table_rows interpolates a safely-quoted name" do
    conn = fake_connection
    client(conn).count_table_rows(table: "emp", owner: "scott")
    assert_equal('SELECT COUNT(*) AS row_count FROM "SCOTT"."EMP"', parsed_sql(conn))

    client(conn).count_table_rows(table: "emp")
    assert_equal('SELECT COUNT(*) AS row_count FROM "EMP"', parsed_sql(conn))
  end

  test "count_table_rows rejects an unsafe identifier" do
    assert_raise(OracleMcp::StatementNotAllowedError) do
      client(fake_connection).count_table_rows(table: "emp; DROP TABLE x")
    end
  end

  test "sample_table caps rows with a bind, defaulting to 100" do
    conn = fake_connection
    client(conn).sample_table(table: "emp")
    assert_equal('SELECT * FROM "EMP" WHERE ROWNUM <= :sample_limit', parsed_sql(conn))
    assert_equal({ ":sample_limit" => 100 }, conn.last_cursor.binds)

    client(conn).sample_table(table: "emp", limit: 5)
    assert_equal({ ":sample_limit" => 5 }, conn.last_cursor.binds)
  end
end
