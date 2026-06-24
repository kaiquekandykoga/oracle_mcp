# frozen_string_literal: true

require "base64"
require "bigdecimal"
require "date"
require "time"

require_relative "errors"

# Operation groups. Each file defines a module under OracleMcp::Operations holding
# the methods for one area (queries, tables, monitoring, ...); Client mixes them
# all in. The directory may be empty during early loading - the glob simply finds
# nothing and no operations are mixed in.
Dir[File.join(__dir__, "operations", "*.rb")].sort.each { |file| require file }

module OracleMcp
  # Namespace for the operation mixins discovered above.
  module Operations; end

  # A thin Oracle Database client built on ruby-oci8.
  #
  # Credentials come from the ORACLE_USER / ORACLE_PASSWORD / ORACLE_DSN
  # environment variables (or constructor arguments). Behaviour is tunable via
  # ORACLE_MCP_READ_ONLY, ORACLE_MCP_MAX_ROWS, ORACLE_MCP_MAX_LOB_BYTES and
  # ORACLE_MCP_QUERY_TIMEOUT.
  #
  # Operation methods (mixed in from {OracleMcp::Operations}) only build SQL and
  # binds, then delegate to the private {#select} (queries) or {#execute}
  # (writes). All connection, fetching, type-coercion and error handling lives
  # here, so operation code never touches OCI8 directly.
  class Client
    DEFAULT_MAX_ROWS = 1000
    DEFAULT_MAX_LOB_BYTES = 1_000_000
    PREFETCH_ROWS = 100

    # Statements allowed by the read-only query path.
    SELECT_KEYWORDS = %w[SELECT WITH].freeze

    # Leading keywords that change rows and so report an affected-row count.
    # Everything else (DDL, PL/SQL blocks, ...) reports a status instead.
    DML_KEYWORDS = %w[INSERT UPDATE DELETE MERGE].freeze

    # Oracle error codes that mean the connection is gone and a reconnect is
    # worth one retry.
    DEAD_CONNECTION_CODES = [28, 1012, 1041, 3113, 3114, 3135, 12152, 12170, 12537, 12541, 12571].freeze

    # Mix in every operation group (Query, Tables, Monitoring, ...).
    Operations.constants.sort.each { |name| include Operations.const_get(name) }

    def initialize(connection: nil, user: nil, password: nil, dsn: nil, privilege: nil,
                   read_only: nil, max_rows: nil, max_lob_bytes: nil, query_timeout: nil)
      @injected_connection = connection
      @user = user || ENV["ORACLE_USER"]
      @password = password || ENV["ORACLE_PASSWORD"]
      @dsn = dsn || ENV["ORACLE_DSN"]
      @privilege = normalize_privilege(privilege || ENV["ORACLE_PRIVILEGE"])
      @read_only = read_only.nil? ? env_bool("ORACLE_MCP_READ_ONLY", false) : read_only
      @max_rows = max_rows || env_int("ORACLE_MCP_MAX_ROWS", DEFAULT_MAX_ROWS)
      @max_lob_bytes = max_lob_bytes || env_int("ORACLE_MCP_MAX_LOB_BYTES", DEFAULT_MAX_LOB_BYTES)
      @query_timeout = query_timeout || env_optional_float("ORACLE_MCP_QUERY_TIMEOUT")

      validate!
    end

    attr_reader :user, :dsn, :max_rows, :max_lob_bytes, :query_timeout

    def read_only?
      @read_only
    end

    # Close the underlying connection, if any. Safe to call repeatedly.
    def close
      conn = @connection
      conn.logoff if conn.respond_to?(:logoff)
    rescue StandardError
      nil
    ensure
      @connection = nil
    end

    private

    # ----- core query/execute -----

    # Run a query and return a result set:
    #   { "columns" => [{ "name" => .., "type" => .. }], "rows" => [[..], ..],
    #     "row_count" => Integer, "truncated" => Boolean }
    # At most +limit+ (or ORACLE_MCP_MAX_ROWS) rows are returned; +truncated+ is
    # true when more rows were available.
    def select(sql, binds: {}, limit: nil, read_safe: false)
      assert_read_safe(sql) if read_safe || read_only?
      max = positive_int(limit) || @max_rows
      guarded do
        cursor = connection.parse(sql)
        begin
          bind_params(cursor, binds)
          with_timeout { cursor.exec }
          build_result_set(cursor, max)
        ensure
          safe_close(cursor)
        end
      end
    end

    # Run a write (DML/DDL). Returns { "rows_affected" => n } for DML or
    # { "status" => "ok" } for DDL. Raises ReadOnlyError when the server is
    # read-only.
    def execute(sql, binds: {})
      if read_only?
        raise ReadOnlyError,
              "Writes are disabled because ORACLE_MCP_READ_ONLY is set. Unset it to allow DML/DDL."
      end

      guarded do
        cursor = connection.parse(sql)
        begin
          bind_params(cursor, binds)
          with_timeout { cursor.exec }
          dml?(sql) ? { "rows_affected" => cursor.row_count } : { "status" => "ok" }
        ensure
          safe_close(cursor)
        end
      end
    end

    def build_result_set(cursor, max)
      columns = cursor.column_metadata.map { |col| { "name" => col.name, "type" => col.data_type.to_s } }
      rows = []
      truncated = false
      while (row = cursor.fetch)
        if rows.length >= max
          truncated = true
          break
        end
        rows << row.map { |value| coerce(value) }
      end
      { "columns" => columns, "rows" => rows, "row_count" => rows.length, "truncated" => truncated }
    end

    # Re-shape a result set into an array of { column_name => value } hashes.
    # Handy for small, wide info/monitoring results where labels aid the reader.
    def rows_as_hashes(result)
      names = result["columns"].map { |column| column["name"] }
      result["rows"].map { |row| names.zip(row).to_h }
    end

    def first_row_hash(result)
      rows_as_hashes(result).first || {}
    end

    # ----- value coercion (OCI8 -> JSON-friendly) -----

    def coerce(value)
      case value
      when nil, Integer, Float, true, false then value
      when BigDecimal then value.frac.zero? ? value.to_i : value.to_f
      when Rational then value.to_f
      when Time, DateTime, Date then value.iso8601
      when String then coerce_string(value)
      else
        value.respond_to?(:read) ? coerce_lob(value) : value.to_s
      end
    end

    # Binary (RAW) strings come back ASCII-8BIT; base64-encode them when they are
    # not valid UTF-8, otherwise return scrubbed UTF-8 text.
    def coerce_string(value)
      if value.encoding == Encoding::ASCII_8BIT && !utf8_valid?(value)
        { "type" => "raw", "base64" => Base64.strict_encode64(value) }
      else
        value.dup.force_encoding(Encoding::UTF_8).scrub
      end
    end

    # CLOB/NCLOB -> text (capped); BLOB -> base64 (capped). Detected by duck
    # typing so this file never references OCI8 constants directly.
    def coerce_lob(lob)
      data, truncated = read_lob(lob)
      if lob.class.name.to_s.upcase.include?("BLOB")
        { "type" => "blob", "base64" => Base64.strict_encode64(data), "truncated" => truncated }
      else
        text = data.dup.force_encoding(Encoding::UTF_8).scrub
        truncated ? "#{text}… [truncated]" : text
      end
    end

    def read_lob(lob)
      data = lob.read(@max_lob_bytes + 1) || ""
      truncated = data.bytesize > @max_lob_bytes
      data = data.byteslice(0, @max_lob_bytes) if truncated
      [data, truncated]
    end

    def utf8_valid?(value)
      value.dup.force_encoding(Encoding::UTF_8).valid_encoding?
    end

    # ----- binds -----

    # Apply binds to a cursor. A Hash binds by name (":name"); an Array binds by
    # 1-based position.
    def bind_params(cursor, binds)
      return if binds.nil? || binds.empty?

      if binds.is_a?(Array)
        binds.each_with_index { |value, index| cursor.bind_param(index + 1, value) }
      else
        binds.each { |key, value| cursor.bind_param(normalize_bind_key(key), value) }
      end
    end

    def normalize_bind_key(key)
      string = key.to_s
      string.start_with?(":") ? string : ":#{string}"
    end

    # ----- read-only safety -----

    # Reject anything that is not a single SELECT/WITH statement.
    def assert_read_safe(sql)
      keyword = statement_keyword(sql)
      unless SELECT_KEYWORDS.include?(keyword)
        raise StatementNotAllowedError,
              "Only SELECT/WITH queries are allowed here (got #{keyword || "an empty statement"})."
      end
      return unless multiple_statements?(sql)

      raise StatementNotAllowedError, "Multiple statements are not allowed in a single call."
    end

    def dml?(sql)
      DML_KEYWORDS.include?(statement_keyword(sql))
    end

    # ----- identifier safety (for the few places that must interpolate names) -----

    # Validate and double-quote a SQL identifier (schema/table/column). Used by
    # convenience tools that select from a named table, where the name cannot be
    # a bind variable. Names are upper-cased to match Oracle's default storage;
    # quoted mixed-case objects are not supported here (use execute_query).
    def quote_ident(name)
      text = name.to_s
      unless text.match?(/\A[A-Za-z][A-Za-z0-9_$#]*\z/)
        raise StatementNotAllowedError, "Invalid SQL identifier: #{name.inspect}"
      end

      %("#{text.upcase}")
    end

    # Build a (optionally owner-qualified) quoted name. A blank owner yields an
    # unqualified name that resolves in the current schema.
    def qualified_name(owner, name)
      parts = []
      parts << quote_ident(owner) unless owner.nil? || owner.to_s.strip.empty?
      parts << quote_ident(name)
      parts.join(".")
    end

    def statement_keyword(sql)
      strip_sql(sql)[/\A([A-Za-z]+)/, 1]&.upcase
    end

    # Strip comments and surrounding whitespace so the leading keyword is visible.
    def strip_sql(sql)
      sql.to_s.gsub(%r{/\*.*?\*/}m, " ").gsub(/--[^\n]*/, " ").strip
    end

    def multiple_statements?(sql)
      strip_sql(sql).sub(/;\s*\z/, "").include?(";")
    end

    # ----- connection + error handling -----

    def connection
      @connection ||= establish_connection
    end

    def establish_connection
      return @injected_connection if @injected_connection

      require "oci8"
      oci = OCI8.new(@user, @password, @dsn, @privilege)
      oci.autocommit = true
      oci.non_blocking = true if oci.respond_to?(:non_blocking=)
      oci.prefetch_rows = PREFETCH_ROWS if oci.respond_to?(:prefetch_rows=)
      oci
    rescue LoadError
      raise ConfigurationError,
            "ruby-oci8 is not installed. Install Oracle Instant Client, then " \
            "`bundle config set --local with oracle && bundle install` (or `gem install ruby-oci8`)."
    rescue OCIError => e
      raise ConnectionError, "Failed to connect to Oracle (#{@dsn}): #{e.message}"
    end

    # Run a block, mapping Oracle errors to library errors. A dropped connection
    # is reconnected and retried once.
    def guarded
      attempts = 0
      begin
        yield
      rescue OCIError => e
        if dead_connection?(e)
          raise ConnectionError, e.message if attempts.positive?

          attempts += 1
          reconnect!
          retry
        end
        raise QueryError, e.message
      end
    end

    def with_timeout
      return yield if @query_timeout.nil?

      require "timeout"
      Timeout.timeout(@query_timeout) { yield }
    rescue Timeout::Error
      break_connection
      raise QueryError, "Query exceeded ORACLE_MCP_QUERY_TIMEOUT (#{@query_timeout}s) and was cancelled."
    end

    def break_connection
      conn = @connection
      conn.break if conn.respond_to?(:break)
    rescue StandardError
      nil
    end

    def dead_connection?(error)
      error.respond_to?(:code) && DEAD_CONNECTION_CODES.include?(error.code)
    end

    def reconnect!
      close
    end

    def safe_close(cursor)
      cursor&.close
    rescue StandardError
      nil
    end

    # ----- configuration -----

    def validate!
      return if @injected_connection

      raise ConfigurationError, "ORACLE_USER is not set" if blank?(@user)
      raise ConfigurationError, "ORACLE_PASSWORD is not set" if blank?(@password)
      raise ConfigurationError, "ORACLE_DSN is not set" if blank?(@dsn)
      raise ConfigurationError, "ORACLE_MCP_MAX_ROWS must be greater than 0" if @max_rows <= 0
    end

    def normalize_privilege(value)
      return nil if value.nil? || value.to_s.strip.empty?

      value.to_s.strip.upcase.to_sym
    end

    def positive_int(value)
      return nil if value.nil?

      number = value.to_i
      number.positive? ? number : nil
    end

    def blank?(value)
      value.nil? || value.empty?
    end

    def env_bool(name, default)
      raw = ENV[name]
      return default if raw.nil? || raw.empty?

      %w[1 true yes on].include?(raw.strip.downcase)
    end

    def env_int(name, default)
      raw = ENV[name]
      return default if raw.nil? || raw.empty?

      Integer(raw, 10)
    rescue ArgumentError
      raise ConfigurationError, "#{name} must be an integer, got #{raw.inspect}"
    end

    def env_optional_float(name)
      raw = ENV[name]
      return nil if raw.nil? || raw.empty?

      Float(raw)
    rescue ArgumentError
      raise ConfigurationError, "#{name} must be a number, got #{raw.inspect}"
    end
  end
end
