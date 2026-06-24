# frozen_string_literal: true

module OracleMcp
  module Tools
    # Tools for indexes, constraints, foreign keys and sequences.
    module Structure
      module_function

      TABLE = Schema.str("Table name. Case-insensitive.")

      def all
        [
          ToolFactory.build(
            name: "list_indexes",
            description: "List indexes on a table, including their columns and uniqueness.",
            properties: { table: TABLE, owner: Schema::OWNER },
            required: %w[table],
            read_only: true,
          ),
          ToolFactory.build(
            name: "list_constraints",
            description: "List constraints on a table (primary key, foreign key, unique, check), with columns.",
            properties: {
              table: TABLE, owner: Schema::OWNER,
              constraint_type: Schema.str("Filter by type: P (primary key), R (foreign key), U (unique), C (check)."),
            },
            required: %w[table],
            read_only: true,
          ),
          ToolFactory.build(
            name: "list_foreign_keys",
            description: "List foreign keys on a table and the columns/tables they reference.",
            properties: { table: TABLE, owner: Schema::OWNER },
            required: %w[table],
            read_only: true,
          ),
          ToolFactory.build(
            name: "list_sequences",
            description: "List sequences in a schema (defaults to the connected user's schema).",
            properties: { owner: Schema::OWNER, name_like: Schema::NAME_LIKE },
            read_only: true,
          ),
        ]
      end
    end
  end
end
