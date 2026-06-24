# frozen_string_literal: true

module OracleMcp
  module Operations
    # DBA/monitoring views (V$ and DBA_*). These require elevated SELECT
    # privileges (e.g. SELECT_CATALOG_ROLE) on the connecting account.
    module Monitoring
      def list_sessions(status: nil, username: nil, include_background: false)
        sql = +<<~SQL
          SELECT sid, serial#, username, status, osuser, machine, program, type,
                 sql_id, logon_time, last_call_et, blocking_session
          FROM v$session
          WHERE 1 = 1
        SQL
        binds = {}
        sql << " AND type = 'USER'" unless include_background
        if status
          sql << " AND status = UPPER(:status)"
          binds[:status] = status
        end
        if username
          sql << " AND username = UPPER(:username)"
          binds[:username] = username
        end
        sql << " ORDER BY last_call_et DESC"
        select(sql, binds: binds)
      end

      def list_blocking_sessions
        select(<<~SQL)
          SELECT bs.sid AS blocker_sid, bs.serial# AS blocker_serial, bs.username AS blocker_user,
                 ws.sid AS waiter_sid, ws.serial# AS waiter_serial, ws.username AS waiter_user,
                 ws.seconds_in_wait, ws.event
          FROM v$session ws
          JOIN v$session bs ON bs.sid = ws.blocking_session
          WHERE ws.blocking_session IS NOT NULL
          ORDER BY ws.seconds_in_wait DESC
        SQL
      end

      def instance_stats
        instance = select("SELECT instance_name, host_name, status, database_status, startup_time FROM v$instance")
        sga = select("SELECT name, ROUND(value / 1024 / 1024, 2) AS mb FROM v$sga")
        stats = select(<<~SQL)
          SELECT name, value FROM v$sysstat
          WHERE name IN ('logons current', 'opened cursors current', 'user commits', 'user rollbacks',
                         'execute count', 'session logical reads', 'physical reads', 'db block changes')
          ORDER BY name
        SQL
        {
          "instance" => first_row_hash(instance),
          "sga" => rows_as_hashes(sga),
          "key_stats" => rows_as_hashes(stats),
        }
      end

      def list_parameters(name_like: nil)
        sql = +"SELECT name, value, isdefault, ismodified, description FROM v$parameter"
        binds = {}
        if name_like
          sql << " WHERE name LIKE LOWER(:name_like)"
          binds[:name_like] = name_like
        end
        sql << " ORDER BY name"
        select(sql, binds: binds)
      end

      def tablespace_usage
        select(<<~SQL)
          SELECT m.tablespace_name,
                 ROUND(m.used_space * t.block_size / 1024 / 1024, 2) AS used_mb,
                 ROUND(m.tablespace_size * t.block_size / 1024 / 1024, 2) AS total_mb,
                 ROUND(m.used_percent, 2) AS used_percent
          FROM dba_tablespace_usage_metrics m
          JOIN dba_tablespaces t ON t.tablespace_name = m.tablespace_name
          ORDER BY m.used_percent DESC
        SQL
      end
    end
  end
end
