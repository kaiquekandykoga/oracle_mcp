# frozen_string_literal: true

module OracleMcp
  module Operations
    # Schemas, tables, views and their columns.
    module Tables
      def list_schemas(name_like: nil)
        sql = +"SELECT username, created FROM all_users"
        binds = {}
        if name_like
          sql << " WHERE username LIKE UPPER(:name_like)"
          binds[:name_like] = name_like
        end
        sql << " ORDER BY username"
        select(sql, binds: binds)
      end

      def list_tables(owner: nil, name_like: nil)
        sql = +"SELECT owner, table_name, num_rows, last_analyzed FROM all_tables " \
               "WHERE owner = NVL(UPPER(:owner), USER)"
        binds = { owner: owner }
        if name_like
          sql << " AND table_name LIKE UPPER(:name_like)"
          binds[:name_like] = name_like
        end
        sql << " ORDER BY table_name"
        select(sql, binds: binds)
      end

      def list_views(owner: nil, name_like: nil)
        sql = +"SELECT owner, view_name FROM all_views WHERE owner = NVL(UPPER(:owner), USER)"
        binds = { owner: owner }
        if name_like
          sql << " AND view_name LIKE UPPER(:name_like)"
          binds[:name_like] = name_like
        end
        sql << " ORDER BY view_name"
        select(sql, binds: binds)
      end

      def describe_table(table:, owner: nil)
        select(<<~SQL, binds: { owner: owner, table_name: table })
          SELECT c.column_id, c.column_name, c.data_type, c.data_length, c.data_precision,
                 c.data_scale, c.nullable, c.data_default, cc.comments
          FROM all_tab_columns c
          LEFT JOIN all_col_comments cc
            ON cc.owner = c.owner AND cc.table_name = c.table_name AND cc.column_name = c.column_name
          WHERE c.owner = NVL(UPPER(:owner), USER) AND c.table_name = UPPER(:table_name)
          ORDER BY c.column_id
        SQL
      end

      def count_table_rows(table:, owner: nil)
        select("SELECT COUNT(*) AS row_count FROM #{qualified_name(owner, table)}")
      end

      def sample_table(table:, owner: nil, limit: nil)
        select(
          "SELECT * FROM #{qualified_name(owner, table)} WHERE ROWNUM <= :sample_limit",
          binds: { sample_limit: positive_int(limit) || 100 },
        )
      end
    end
  end
end
