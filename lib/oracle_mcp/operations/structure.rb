# frozen_string_literal: true

module OracleMcp
  module Operations
    # Indexes, constraints, foreign keys and sequences.
    module Structure
      def list_indexes(table:, owner: nil)
        select(<<~SQL, binds: { owner: owner, table_name: table })
          SELECT i.index_name, i.uniqueness, i.index_type, i.status,
                 ic.column_name, ic.column_position
          FROM all_indexes i
          JOIN all_ind_columns ic
            ON ic.index_owner = i.owner AND ic.index_name = i.index_name
          WHERE i.table_owner = NVL(UPPER(:owner), USER) AND i.table_name = UPPER(:table_name)
          ORDER BY i.index_name, ic.column_position
        SQL
      end

      def list_constraints(table:, owner: nil, constraint_type: nil)
        sql = +<<~SQL
          SELECT c.constraint_name, c.constraint_type, c.search_condition, c.r_constraint_name,
                 c.status, cc.column_name, cc.position
          FROM all_constraints c
          LEFT JOIN all_cons_columns cc
            ON cc.owner = c.owner AND cc.constraint_name = c.constraint_name
          WHERE c.owner = NVL(UPPER(:owner), USER) AND c.table_name = UPPER(:table_name)
        SQL
        binds = { owner: owner, table_name: table }
        if constraint_type
          sql << " AND c.constraint_type = UPPER(:constraint_type)"
          binds[:constraint_type] = constraint_type
        end
        sql << " ORDER BY c.constraint_name, cc.position"
        select(sql, binds: binds)
      end

      def list_foreign_keys(table:, owner: nil)
        select(<<~SQL, binds: { owner: owner, table_name: table })
          SELECT c.constraint_name, a.column_name, a.position,
                 rc.owner AS referenced_owner, rc.table_name AS referenced_table,
                 rcc.column_name AS referenced_column, c.delete_rule, c.status
          FROM all_constraints c
          JOIN all_cons_columns a
            ON a.owner = c.owner AND a.constraint_name = c.constraint_name
          JOIN all_constraints rc
            ON rc.owner = c.r_owner AND rc.constraint_name = c.r_constraint_name
          JOIN all_cons_columns rcc
            ON rcc.owner = rc.owner AND rcc.constraint_name = rc.constraint_name AND rcc.position = a.position
          WHERE c.owner = NVL(UPPER(:owner), USER)
            AND c.table_name = UPPER(:table_name)
            AND c.constraint_type = 'R'
          ORDER BY c.constraint_name, a.position
        SQL
      end

      def list_sequences(owner: nil, name_like: nil)
        sql = +"SELECT sequence_owner, sequence_name, min_value, max_value, increment_by, " \
               "last_number, cache_size, cycle_flag FROM all_sequences " \
               "WHERE sequence_owner = NVL(UPPER(:owner), USER)"
        binds = { owner: owner }
        if name_like
          sql << " AND sequence_name LIKE UPPER(:name_like)"
          binds[:name_like] = name_like
        end
        sql << " ORDER BY sequence_name"
        select(sql, binds: binds)
      end
    end
  end
end
