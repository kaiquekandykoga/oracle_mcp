# frozen_string_literal: true

require_relative "../test_helper"

class DatabaseOperationsTest < Test::Unit::TestCase
  include TestHelpers

  test "get_database_info gathers version, instance, database and session" do
    conn = fake_connection
    result = build_client(connection: conn).get_database_info
    joined = conn.parsed.map { |sql| normalize_sql(sql) }.join(" | ")

    assert_match(/product_component_version/, joined)
    assert_match(/v\$instance/, joined)
    assert_match(/v\$database/, joined)
    assert_match(/CURRENT_SCHEMA/, joined)
    assert_equal(%w[database instance session version], result.keys.sort)
  end

  test "ping runs SELECT 1 FROM dual and reports ok" do
    conn = fake_connection
    result = build_client(connection: conn).ping
    assert_equal("SELECT 1 FROM dual", conn.parsed.last)
    assert_equal({ "ok" => true }, result)
  end
end
