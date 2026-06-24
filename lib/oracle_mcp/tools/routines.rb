# frozen_string_literal: true

module OracleMcp
  module Tools
    # Tools for stored program units and object DDL.
    module Routines
      module_function

      def all
        [
          ToolFactory.build(
            name: "list_procedures",
            description: "List standalone stored procedures in a schema (defaults to the connected user).",
            properties: { owner: Schema::OWNER, name_like: Schema::NAME_LIKE },
            read_only: true,
          ),
          ToolFactory.build(
            name: "list_functions",
            description: "List standalone stored functions in a schema (defaults to the connected user).",
            properties: { owner: Schema::OWNER, name_like: Schema::NAME_LIKE },
            read_only: true,
          ),
          ToolFactory.build(
            name: "list_packages",
            description: "List PL/SQL packages in a schema (defaults to the connected user).",
            properties: { owner: Schema::OWNER, name_like: Schema::NAME_LIKE },
            read_only: true,
          ),
          ToolFactory.build(
            name: "list_objects",
            description: "List database objects of any type in a schema, optionally filtered by type.",
            properties: {
              owner: Schema::OWNER,
              object_type: Schema.str("Filter by object type, e.g. TABLE, VIEW, TRIGGER, PACKAGE, INDEX."),
              name_like: Schema::NAME_LIKE,
            },
            read_only: true,
          ),
          ToolFactory.build(
            name: "get_object_ddl",
            description: "Generate the CREATE DDL for an object via DBMS_METADATA.",
            properties: {
              object_type: Schema.str("Object type, e.g. TABLE, VIEW, INDEX, PACKAGE, PROCEDURE, FUNCTION, SEQUENCE, TRIGGER."),
              name: Schema::OBJECT_NAME,
              owner: Schema::OWNER,
            },
            required: %w[object_type name],
            read_only: true,
          ),
        ]
      end
    end
  end
end
