# frozen_string_literal: true
require 'pg'
require 'digest'
module Database
  def self.migrate(connection)
    connection.transaction do
      connection.exec("SELECT pg_advisory_xact_lock(727456820)")
      connection.exec('CREATE SCHEMA IF NOT EXISTS juridico')
      connection.exec('REVOKE ALL ON SCHEMA juridico FROM PUBLIC')
      connection.exec('CREATE TABLE IF NOT EXISTS juridico.schema_migrations(version TEXT PRIMARY KEY, sha256 TEXT NOT NULL)')
      Dir[File.join(__dir__, 'migrations', '*.sql')].sort.each do |path|
        version, sql = File.basename(path), File.read(path)
        sha = Digest::SHA256.hexdigest(sql)
        existing = connection.exec_params('SELECT sha256 FROM juridico.schema_migrations WHERE version=$1', [version])
        if existing.ntuples.positive?
          raise 'Migration aplicada foi alterada.' unless existing.first['sha256'] == sha
          next
        end
        connection.exec(sql)
        connection.exec_params('INSERT INTO juridico.schema_migrations VALUES ($1,$2)', [version, sha])
      end
    end
  end
end
