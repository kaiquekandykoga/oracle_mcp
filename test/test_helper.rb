# frozen_string_literal: true

require "json"
require "stringio"
require "bigdecimal"
require "date"
require "time"

require "oracle_mcp"
require "test/unit"

# ruby-oci8 raises OCIError (carrying an Oracle error #code). The gem is not a
# hard dependency and is absent in CI, so define a faithful stand-in when it is
# missing. The Client only relies on #message and #code.
unless defined?(OCIError)
  class OCIError < StandardError
    attr_reader :code

    def initialize(message = "", code = nil)
      super(message)
      @code = code
    end
  end
end

# A scripted stand-in for an OCI8 column descriptor.
class FakeColumn
  attr_reader :name, :data_type

  def initialize(name, data_type = :varchar2)
    @name = name
    @data_type = data_type
  end
end

# A scripted stand-in for an OCI8::Cursor. Records the SQL it was parsed from and
# every bind applied, then serves canned column metadata and rows.
class FakeCursor
  attr_reader :sql, :binds

  def initialize(owner, sql)
    @owner = owner
    @sql = sql
    @binds = {}
    @rows = nil
  end

  def bind_param(key, value)
    @binds[key] = value
    self
  end

  def exec
    @owner.before_exec
    error = @owner.next_exec_error
    raise error if error

    @owner.response_for(@sql)[:rows].length
  end

  def column_metadata
    @owner.response_for(@sql)[:columns]
  end

  def fetch
    @rows ||= @owner.response_for(@sql)[:rows].map(&:dup)
    @rows.shift
  end

  def row_count
    @owner.response_for(@sql)[:row_count]
  end

  def close; end
end

# A scripted stand-in for an OCI8 connection. Programmable with a default
# response (columns/rows/row_count) and/or a per-SQL responder block, plus a
# queue of errors to raise on successive exec calls (for retry/error tests).
class FakeOCI8
  attr_reader :parsed, :cursors, :logoff_count

  def initialize(default = {}, &responder)
    @default = normalize_response(default)
    @responder = responder
    @parsed = []
    @cursors = []
    @exec_errors = []
    @exec_sleep = nil
    @logoff_count = 0
    @broken = false
  end

  # Program errors raised on successive exec calls (nil entries = success).
  def fail_execs_with(*errors)
    @exec_errors.concat(errors)
    self
  end

  # Make every exec sleep this long (to exercise query timeouts).
  def sleep_on_exec(seconds)
    @exec_sleep = seconds
    self
  end

  def next_exec_error
    @exec_errors.shift
  end

  def before_exec
    sleep(@exec_sleep) if @exec_sleep
  end

  def response_for(sql)
    resp = @responder&.call(sql)
    resp ? normalize_response(resp) : @default
  end

  def parse(sql)
    @parsed << sql
    cursor = FakeCursor.new(self, sql)
    @cursors << cursor
    cursor
  end

  def last_cursor
    @cursors.last
  end

  def autocommit=(_value); end
  def non_blocking=(_value); end
  def prefetch_rows=(_value); end

  def break
    @broken = true
  end

  def broken?
    @broken
  end

  def logoff
    @logoff_count += 1
  end

  private

  def normalize_response(resp)
    rows = resp[:rows] || []
    {
      columns: resp[:columns] || [],
      rows: rows,
      row_count: resp[:row_count] || rows.length,
    }
  end
end

# A duck-typed CLOB: reads as text.
class FakeClob
  def initialize(data)
    @data = data.dup.force_encoding(Encoding::UTF_8)
  end

  def read(length = nil)
    length ? @data.byteslice(0, length) : @data
  end
end

# A duck-typed BLOB: reads as binary (class name contains "BLOB").
class FakeBlob
  def initialize(data)
    @data = data.b
  end

  def read(length = nil)
    length ? @data.byteslice(0, length) : @data
  end
end

# Shared helpers for exercising the client, operations and tools.
module TestHelpers
  # Build a client backed by a fake connection (defaults to an empty result set).
  def build_client(connection: nil, **opts)
    connection ||= FakeOCI8.new
    OracleMcp::Client.new(connection: connection, **opts)
  end

  # Build a fake connection returning the given columns/rows for every query.
  def fake_connection(columns: [], rows: [], row_count: nil, &block)
    FakeOCI8.new({ columns: columns, rows: rows, row_count: row_count }, &block)
  end

  def col(name, type = :varchar2)
    FakeColumn.new(name, type)
  end

  def oci_error(message, code)
    OCIError.new(message, code)
  end

  # Collapse whitespace so heredoc SQL can be matched without caring about layout.
  def normalize_sql(sql)
    sql.to_s.gsub(/\s+/, " ").strip
  end

  # Normalized text of the (default: last) SQL the fake connection parsed.
  def parsed_sql(connection, index = -1)
    normalize_sql(connection.parsed[index])
  end

  # Run the block with the given environment, restoring the original afterwards.
  def with_env(values)
    original = ENV.to_hash
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    ENV.replace(original)
  end

  # Capture everything written to $stdout while the block runs.
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
