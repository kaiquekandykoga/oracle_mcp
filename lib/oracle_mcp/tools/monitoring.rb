# frozen_string_literal: true

module OracleMcp
  module Tools
    # Tools for DBA/monitoring views (require elevated SELECT privileges).
    module Monitoring
      module_function

      def all
        [
          ToolFactory.build(
            name: "list_sessions",
            description: "List database sessions from V$SESSION (user sessions by default).",
            properties: {
              status: Schema.str("Filter by status, e.g. ACTIVE or INACTIVE."),
              username: Schema.str("Filter by session username."),
              include_background: Schema.bool("Include background (non-USER) sessions. Default false."),
            },
            read_only: true,
          ),
          ToolFactory.build(
            name: "list_blocking_sessions",
            description: "List sessions that are blocking other sessions, with the waiters and wait events.",
            read_only: true,
          ),
          ToolFactory.build(
            name: "instance_stats",
            description: "Return instance status, SGA component sizes and key activity statistics.",
            read_only: true,
          ),
          ToolFactory.build(
            name: "list_parameters",
            description: "List initialization parameters from V$PARAMETER.",
            properties: { name_like: Schema.str('Optional case-insensitive parameter-name LIKE filter, e.g. "%cache%".') },
            read_only: true,
          ),
          ToolFactory.build(
            name: "tablespace_usage",
            description: "Report tablespace space usage (used/total MB and percent) from DBA views.",
            read_only: true,
          ),
        ]
      end
    end
  end
end
