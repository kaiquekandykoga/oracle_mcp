# frozen_string_literal: true

require_relative "../test_helper"

class StructureOperationsTest < Test::Unit::TestCase
  include TestHelpers

  def client(conn)
    build_client(connection: conn)
  end

  test "list_indexes joins all_indexes with its columns" do
    conn = fake_connection
    client(conn).list_indexes(table: "emp", owner: "scott")
    sql = parsed_sql(conn)
    assert_match(/FROM all_indexes i/, sql)
    assert_match(/all_ind_columns ic/, sql)
    assert_equal({ ":owner" => "scott", ":table_name" => "emp" }, conn.last_cursor.binds)
  end

  test "list_constraints can filter by constraint type" do
    conn = fake_connection
    client(conn).list_constraints(table: "emp")
    assert_match(/FROM all_constraints c/, parsed_sql(conn))
    assert_equal({ ":owner" => nil, ":table_name" => "emp" }, conn.last_cursor.binds)

    client(conn).list_constraints(table: "emp", constraint_type: "P")
    assert_match(/AND c.constraint_type = UPPER\(:constraint_type\)/, parsed_sql(conn))
    assert_equal({ ":owner" => nil, ":table_name" => "emp", ":constraint_type" => "P" }, conn.last_cursor.binds)
  end

  test "list_foreign_keys selects referential constraints" do
    conn = fake_connection
    client(conn).list_foreign_keys(table: "emp")
    sql = parsed_sql(conn)
    assert_match(/c.constraint_type = 'R'/, sql)
    assert_match(/referenced_table/, sql)
    assert_equal({ ":owner" => nil, ":table_name" => "emp" }, conn.last_cursor.binds)
  end

  test "list_sequences queries all_sequences" do
    conn = fake_connection
    client(conn).list_sequences(name_like: "SEQ%")
    assert_match(/FROM all_sequences WHERE sequence_owner = NVL\(UPPER\(:owner\), USER\)/, parsed_sql(conn))
    assert_equal({ ":owner" => nil, ":name_like" => "SEQ%" }, conn.last_cursor.binds)
  end
end
