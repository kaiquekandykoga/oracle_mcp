# frozen_string_literal: true

module OracleMcp
  # Base class for every error raised by this library.
  class Error < StandardError; end

  # Raised when required configuration (credentials, tuning) is missing or invalid.
  class ConfigurationError < Error; end

  # Raised when a database connection cannot be established or is lost.
  class ConnectionError < Error; end

  # Raised when Oracle rejects a statement or returns an error. The message
  # carries Oracle's own ORA-xxxxx text.
  class QueryError < Error; end

  # Raised when a write (DML/DDL) is attempted while the server is read-only.
  class ReadOnlyError < Error; end

  # Raised when a statement is not permitted in the current context, e.g. a
  # non-SELECT passed to the read-only query tool.
  class StatementNotAllowedError < Error; end
end
