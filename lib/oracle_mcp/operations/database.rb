# frozen_string_literal: true

module OracleMcp
  module Operations
    # Database/instance identity and connectivity checks.
    module Database
      # Version, instance, database and session identity in one call.
      def get_database_info
        {
          "version" => rows_as_hashes(
            select("SELECT product, version, status FROM product_component_version"),
          ),
          "instance" => first_row_hash(
            select("SELECT instance_name, host_name, version, status, database_status, startup_time FROM v$instance"),
          ),
          "database" => first_row_hash(
            select("SELECT name, db_unique_name, open_mode, database_role, log_mode, created FROM v$database"),
          ),
          "session" => first_row_hash(
            select(<<~SQL),
              SELECT USER AS current_user,
                     SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AS current_schema,
                     SYS_CONTEXT('USERENV', 'DB_NAME') AS db_name
              FROM dual
            SQL
          ),
        }
      end

      # Confirm the connection is alive.
      def ping
        select("SELECT 1 FROM dual")
        { "ok" => true }
      end
    end
  end
end
