# frozen_string_literal: true

require_relative "schema"
require_relative "tool_factory"

# Each file defines a module under OracleMcp::Tools exposing `.all`, an array of
# MCP::Tool objects for one area. The directory may be empty during early
# loading - the glob simply finds nothing.
Dir[File.join(__dir__, "tools", "*.rb")].sort.each { |file| require file }

module OracleMcp
  # Aggregates every tool category into a single list for the server.
  module Tools
    module_function

    # All tools across every category, sorted by name for stable ordering.
    def all
      categories.flat_map(&:all).sort_by(&:name_value)
    end

    # The category modules (Query, Tables, Monitoring, ...) that expose `.all`.
    def categories
      constants
        .map { |const| const_get(const) }
        .select { |value| value.is_a?(Module) && value.respond_to?(:all) }
    end
  end
end
