# frozen_string_literal: true

module OracleMcp
  # Helpers for building JSON Schema property fragments used by tool input
  # schemas. Keeping these in one place makes the tool definitions concise and
  # consistent.
  module Schema
    module_function

    # A string property.
    def str(description) = { type: "string", description: description }

    # An integer property.
    def int(description) = { type: "integer", description: description }

    # A boolean property.
    def bool(description) = { type: "boolean", description: description }

    # An array-of-strings property.
    def strs(description) = { type: "array", items: { type: "string" }, description: description }

    # A free-form array property (items may be any type).
    def array(description) = { type: "array", description: description }

    # A free-form object property (arbitrary nested shape). Deliberately omits
    # additionalProperties so MCP input validation accepts any nested value.
    def object(description) = { type: "object", description: description }

    # A property with no declared type: any JSON value is accepted. Used where an
    # argument may legitimately be more than one type (e.g. binds as an object or
    # an array).
    def any(description) = { description: description }

    # Shared properties that appear across many tools.
    OWNER = str(
      "Schema/owner that owns the object. Defaults to the connected user when omitted. Case-insensitive.",
    ).freeze
    OBJECT_NAME = str("Object name. Case-insensitive.").freeze
    NAME_LIKE = str('Optional case-insensitive name filter as a SQL LIKE pattern, e.g. "EMP%".').freeze
    BINDS = any(
      "Optional bind variables. Use an object of name => value for named binds (:name in the SQL), " \
      "or an array for positional binds (:1, :2, ...). Always prefer binds over string interpolation.",
    ).freeze
    LIMIT = int("Maximum number of rows to return (additionally capped by ORACLE_MCP_MAX_ROWS).").freeze
  end
end
