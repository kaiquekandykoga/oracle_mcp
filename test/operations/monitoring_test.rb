# frozen_string_literal: true

require_relative "../test_helper"

class MonitoringOperationsTest < Test::Unit::TestCase
  include TestHelpers

  def client(conn)
    build_client(connection: conn)
  end

  test "list_sessions shows user sessions by default and supports filters" do
    conn = fake_connection
    client(conn).list_sessions
    sql = parsed_sql(conn)
    assert_match(/FROM v\$session/, sql)
    assert_match(/AND type = 'USER'/, sql)
    assert_equal({}, conn.last_cursor.binds)

    client(conn).list_sessions(status: "active", username: "scott", include_background: true)
    sql = parsed_sql(conn)
    assert_not_match(/type = 'USER'/, sql)
    assert_match(/AND status = UPPER\(:status\)/, sql)
    assert_equal({ ":status" => "active", ":username" => "scott" }, conn.last_cursor.binds)
  end

  test "list_blocking_sessions joins blockers and waiters" do
    conn = fake_connection
    client(conn).list_blocking_sessions
    sql = parsed_sql(conn)
    assert_match(/blocking_session IS NOT NULL/, sql)
    assert_match(/blocker_sid/, sql)
  end

  test "instance_stats gathers instance, SGA and key statistics" do
    conn = fake_connection
    result = client(conn).instance_stats
    joined = conn.parsed.map { |sql| normalize_sql(sql) }.join(" | ")
    assert_match(/v\$instance/, joined)
    assert_match(/v\$sga/, joined)
    assert_match(/v\$sysstat/, joined)
    assert_equal(%w[instance key_stats sga], result.keys.sort)
  end

  test "list_parameters queries v$parameter, optionally filtered" do
    conn = fake_connection
    client(conn).list_parameters(name_like: "%cache%")
    assert_match(/FROM v\$parameter/, parsed_sql(conn))
    assert_match(/WHERE name LIKE LOWER\(:name_like\)/, parsed_sql(conn))
    assert_equal({ ":name_like" => "%cache%" }, conn.last_cursor.binds)
  end

  test "tablespace_usage reports usage from DBA views" do
    conn = fake_connection
    client(conn).tablespace_usage
    sql = parsed_sql(conn)
    assert_match(/dba_tablespace_usage_metrics/, sql)
    assert_match(/used_percent/, sql)
  end
end
