# frozen_string_literal: true

module OracleMcp
  module Tools
    # Tools for database identity and connectivity.
    module Database
      module_function

      def all
        [
          ToolFactory.build(
            name: "get_database_info",
            description: "Return database, instance, version and session identity information.",
            read_only: true,
          ),
          ToolFactory.build(
            name: "ping",
            description: "Check that the database connection is alive (SELECT 1 FROM dual).",
            read_only: true,
          ),
        ]
      end
    end
  end
end
