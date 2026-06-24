# frozen_string_literal: true

require_relative "lib/oracle_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "oracle_mcp"
  spec.version = OracleMcp::VERSION
  spec.authors = ["Kaíque Kandy Koga"]
  spec.summary = "MCP server exposing an Oracle Database to any MCP-compatible client."
  spec.description = <<~DESC
    A Model Context Protocol (MCP) server that exposes an Oracle Database as tools
    any MCP-compatible client (Claude, editors, agents) can call: run SQL, inspect
    schema, generate DDL, and monitor the instance. Connects via ruby-oci8.

    Runtime dependencies are minimal (the MCP SDK and dotenv). ruby-oci8 links
    against Oracle Instant Client and is installed separately - see the README.
  DESC
  spec.homepage = "https://github.com/kaiquekandykoga/oracle_mcp"
  spec.license = "BSD-3-Clause"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/releases"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "bin/*", "README.md", "LICENSE"]
  spec.bindir = "bin"
  spec.executables = ["oracle-mcp"]
  spec.require_paths = ["lib"]

  spec.add_dependency "base64", "~> 0.2"
  spec.add_dependency "dotenv", "~> 3.2"
  spec.add_dependency "mcp", "~> 0.21"

  spec.add_development_dependency "rake", "~> 13.4"
  spec.add_development_dependency "rubocop", "~> 1.88"
  spec.add_development_dependency "test-unit", "~> 3.7"
end
