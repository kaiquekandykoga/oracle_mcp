# frozen_string_literal: true

module OracleMcp
  module Operations
    # Arbitrary SQL execution and plan analysis.
    module Query
      # Run a SELECT/WITH query and return the result set. Always read-safe:
      # non-SELECT statements are rejected here even when writes are enabled
      # globally (use execute_statement for those).
      def execute_query(sql:, binds: nil, limit: nil)
        select(sql, binds: binds || {}, limit: limit, read_safe: true)
      end

      # Run a single DML or DDL statement (INSERT/UPDATE/DELETE/MERGE, or
      # CREATE/ALTER/DROP/...). Refused when the server is read-only.
      def execute_statement(sql:, binds: nil)
        execute(sql, binds: binds || {})
      end

      # Run an anonymous PL/SQL block. Refused when the server is read-only.
      def execute_plsql(plsql:, binds: nil)
        execute(plsql, binds: binds || {})
      end

      # Return the execution plan for a statement without running it. Writes to
      # PLAN_TABLE, so it also requires write access (refused when read-only).
      def explain_plan(sql:)
        execute("EXPLAIN PLAN FOR #{sql}")
        result = select("SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY)")
        result["rows"].map(&:first).join("\n")
      end
    end
  end
end
