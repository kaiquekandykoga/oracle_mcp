# frozen_string_literal: true

require_relative "../test_helper"

class RoutinesOperationsTest < Test::Unit::TestCase
  include TestHelpers

  def client(conn)
    build_client(connection: conn)
  end

  test "list_procedures/functions/packages filter all_objects by type" do
    conn = fake_connection

    client(conn).list_procedures
    assert_match(/FROM all_objects WHERE owner = NVL\(UPPER\(:owner\), USER\) AND object_type = :object_type/, parsed_sql(conn))
    assert_equal({ ":owner" => nil, ":object_type" => "PROCEDURE" }, conn.last_cursor.binds)

    client(conn).list_functions
    assert_equal({ ":owner" => nil, ":object_type" => "FUNCTION" }, conn.last_cursor.binds)

    client(conn).list_packages(owner: "scott")
    assert_equal({ ":owner" => "scott", ":object_type" => "PACKAGE" }, conn.last_cursor.binds)
  end

  test "list_objects can filter by type and name" do
    conn = fake_connection
    client(conn).list_objects(object_type: "TRIGGER", name_like: "TRG%")
    sql = parsed_sql(conn)
    assert_match(/FROM all_objects/, sql)
    assert_match(/AND object_type = UPPER\(:object_type\)/, sql)
    assert_match(/AND object_name LIKE UPPER\(:name_like\)/, sql)
    assert_equal({ ":owner" => nil, ":object_type" => "TRIGGER", ":name_like" => "TRG%" }, conn.last_cursor.binds)
  end

  test "get_object_ddl calls DBMS_METADATA and returns DDL text" do
    conn = fake_connection(columns: [col("DDL", :clob)], rows: [["CREATE TABLE EMP (...)"]])
    result = client(conn).get_object_ddl(object_type: "table", name: "emp")

    assert_match(/DBMS_METADATA.GET_DDL\(UPPER\(:object_type\), UPPER\(:name\), NVL\(UPPER\(:owner\), USER\)\)/, parsed_sql(conn))
    assert_equal({ ":object_type" => "table", ":name" => "emp", ":owner" => nil }, conn.last_cursor.binds)
    assert_equal("CREATE TABLE EMP (...)", result)
  end
end
