# frozen_string_literal: true

module OracleMcp
  module Operations
    # Stored program units (procedures, functions, packages) and object DDL.
    module Routines
      def list_procedures(owner: nil, name_like: nil)
        list_objects_of_type("PROCEDURE", owner: owner, name_like: name_like)
      end

      def list_functions(owner: nil, name_like: nil)
        list_objects_of_type("FUNCTION", owner: owner, name_like: name_like)
      end

      def list_packages(owner: nil, name_like: nil)
        list_objects_of_type("PACKAGE", owner: owner, name_like: name_like)
      end

      # List any objects, optionally filtered by type (TABLE, VIEW, TRIGGER, ...).
      def list_objects(owner: nil, object_type: nil, name_like: nil)
        sql = +"SELECT owner, object_name, object_type, status, created, last_ddl_time " \
               "FROM all_objects WHERE owner = NVL(UPPER(:owner), USER)"
        binds = { owner: owner }
        if object_type
          sql << " AND object_type = UPPER(:object_type)"
          binds[:object_type] = object_type
        end
        if name_like
          sql << " AND object_name LIKE UPPER(:name_like)"
          binds[:name_like] = name_like
        end
        sql << " ORDER BY object_type, object_name"
        select(sql, binds: binds)
      end

      # Generate the DDL for an object via DBMS_METADATA. Returns the DDL text.
      def get_object_ddl(object_type:, name:, owner: nil)
        result = select(
          "SELECT DBMS_METADATA.GET_DDL(UPPER(:object_type), UPPER(:name), NVL(UPPER(:owner), USER)) AS ddl FROM dual",
          binds: { object_type: object_type, name: name, owner: owner },
        )
        ddl = result["rows"].dig(0, 0)
        ddl.nil? ? "" : ddl.to_s
      end

      private

      def list_objects_of_type(object_type, owner:, name_like:)
        sql = +"SELECT owner, object_name, object_type, status, created, last_ddl_time " \
               "FROM all_objects WHERE owner = NVL(UPPER(:owner), USER) AND object_type = :object_type"
        binds = { owner: owner, object_type: object_type }
        if name_like
          sql << " AND object_name LIKE UPPER(:name_like)"
          binds[:name_like] = name_like
        end
        sql << " ORDER BY object_name"
        select(sql, binds: binds)
      end
    end
  end
end
