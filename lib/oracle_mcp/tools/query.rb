# frozen_string_literal: true

module OracleMcp
  module Tools
    # Tools for arbitrary SQL execution and plan analysis.
    module Query
      module_function

      def all
        [
          ToolFactory.build(
            name: "execute_query",
            description: "Run a read-only SELECT/WITH query and return the rows. Prefer bind variables " \
                         "over string interpolation. Results are capped by ORACLE_MCP_MAX_ROWS; the " \
                         "response sets \"truncated\": true when more rows were available.",
            properties: { sql: Schema.str("The SELECT or WITH statement to run."), binds: Schema::BINDS, limit: Schema::LIMIT },
            required: %w[sql],
            read_only: true,
          ),
          ToolFactory.build(
            name: "execute_statement",
            description: "Run a single DML or DDL statement (INSERT/UPDATE/DELETE/MERGE or " \
                         "CREATE/ALTER/DROP/...). Returns affected-row count (DML) or status (DDL). " \
                         "Disabled when ORACLE_MCP_READ_ONLY is set.",
            properties: { sql: Schema.str("The DML or DDL statement to run."), binds: Schema::BINDS },
            required: %w[sql],
            destructive: true,
          ),
          ToolFactory.build(
            name: "execute_plsql",
            description: "Run an anonymous PL/SQL block (BEGIN ... END; or DECLARE ...). " \
                         "Disabled when ORACLE_MCP_READ_ONLY is set.",
            properties: { plsql: Schema.str("The PL/SQL block to run."), binds: Schema::BINDS },
            required: %w[plsql],
            destructive: true,
          ),
          ToolFactory.build(
            name: "explain_plan",
            description: "Return the execution plan for a statement without running its logic. " \
                         "Writes to PLAN_TABLE, so it requires write access (disabled when read-only).",
            properties: { sql: Schema.str("The statement to explain.") },
            required: %w[sql],
          ),
        ]
      end
    end
  end
end
