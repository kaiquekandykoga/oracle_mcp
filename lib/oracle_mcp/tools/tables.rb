# frozen_string_literal: true

module OracleMcp
  module Tools
    # Tools for schemas, tables, views and their columns.
    module Tables
      module_function

      TABLE = Schema.str("Table name. Case-insensitive.")

      def all
        [
          ToolFactory.build(
            name: "list_schemas",
            description: "List database schemas (users).",
            properties: { name_like: Schema::NAME_LIKE },
            read_only: true,
          ),
          ToolFactory.build(
            name: "list_tables",
            description: "List tables in a schema (defaults to the connected user's schema).",
            properties: { owner: Schema::OWNER, name_like: Schema::NAME_LIKE },
            read_only: true,
          ),
          ToolFactory.build(
            name: "list_views",
            description: "List views in a schema (defaults to the connected user's schema).",
            properties: { owner: Schema::OWNER, name_like: Schema::NAME_LIKE },
            read_only: true,
          ),
          ToolFactory.build(
            name: "describe_table",
            description: "Describe a table or view: columns with data types, nullability, defaults and comments.",
            properties: { table: TABLE, owner: Schema::OWNER },
            required: %w[table],
            read_only: true,
          ),
          ToolFactory.build(
            name: "count_table_rows",
            description: "Count the rows in a table (live COUNT(*)).",
            properties: { table: TABLE, owner: Schema::OWNER },
            required: %w[table],
            read_only: true,
          ),
          ToolFactory.build(
            name: "sample_table",
            description: "Return a small sample of rows from a table to preview its data.",
            properties: { table: TABLE, owner: Schema::OWNER, limit: Schema.int("Maximum rows to sample (default 100).") },
            required: %w[table],
            read_only: true,
          ),
        ]
      end
    end
  end
end
