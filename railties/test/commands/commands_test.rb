# frozen_string_literal: true

require "isolation/abstract_unit"
require "rails/command"
require "json"
require "yaml"

class Rails::Command::CommandsTest < ActiveSupport::TestCase
  setup :build_app
  teardown :teardown_app

  test "commands outputs table format by default" do
    output = run_commands_command

    assert_match(/KIND/, output)
    assert_match(/COMMAND/, output)
    assert_match(/DESCRIPTION/, output)
    assert_match(/routes/, output)
  end

  test "commands includes schema_version and rails_version in JSON output" do
    output = run_commands_command(["--format=json"])
    result = JSON.parse(output)

    assert_equal "1.0", result["schema_version"]
    assert result["rails_version"].present?
  end

  test "commands lists Thor-based commands with metadata" do
    output = run_commands_command(["--format=json"])
    result = JSON.parse(output)

    routes_command = result["commands"].find { |c| c["full_name"] == "routes" }
    assert_not_nil routes_command, "Expected to find 'routes' command"
    assert_equal "thor", routes_command["kind"]
    assert routes_command["description"].present?
  end

  test "commands includes options for Thor commands" do
    output = run_commands_command(["--format=json"])
    result = JSON.parse(output)

    routes_command = result["commands"].find { |c| c["full_name"] == "routes" }
    assert_not_nil routes_command

    options = routes_command["options"]
    assert_kind_of Array, options

    controller_option = options.find { |o| o["name"] == "--controller" }
    assert_not_nil controller_option, "Expected routes to have --controller option"
    assert_includes controller_option["aliases"], "-c"
    assert_equal "string", controller_option["type"]
  end

  test "commands lists Rake tasks" do
    output = run_commands_command(["--format=json"])
    result = JSON.parse(output)

    db_migrate = result["commands"].find { |c| c["full_name"] == "db:migrate" }
    assert_not_nil db_migrate, "Expected to find 'db:migrate' rake task"
    assert_equal "rake", db_migrate["kind"]
    assert db_migrate["description"].present?
  end

  test "commands excludes Rake tasks with --no-rake" do
    output = run_commands_command(["--format=json", "--no-rake"])
    result = JSON.parse(output)

    rake_commands = result["commands"].select { |c| c["kind"] == "rake" }
    assert_empty rake_commands, "Expected no rake tasks when --no-rake is passed"

    thor_commands = result["commands"].select { |c| c["kind"] == "thor" }
    assert_not_empty thor_commands, "Expected Thor commands to still be present"
  end

  test "commands excludes hidden commands by default" do
    output = run_commands_command(["--format=json"])
    result = JSON.parse(output)

    help_command = result["commands"].find { |c| c["full_name"] == "help" }
    assert_nil help_command, "Expected hidden 'help' command to be excluded by default"
  end

  test "commands excludes help subcommands by default" do
    output = run_commands_command(["--format=json"])
    result = JSON.parse(output)

    help_subcommands = result["commands"].select { |c| c["full_name"].end_with?(":help") }
    assert_empty help_subcommands, "Expected :help subcommands to be excluded by default"
  end

  test "commands includes help subcommands with --all flag" do
    output = run_commands_command(["--format=json", "--all"])
    result = JSON.parse(output)

    help_subcommands = result["commands"].select { |c| c["full_name"].end_with?(":help") }
    assert_not_empty help_subcommands, "Expected :help subcommands with --all flag"
  end

  test "commands includes hidden commands with --all flag" do
    output = run_commands_command(["--format=json", "--all"])
    result = JSON.parse(output)

    hidden_commands = result["commands"].select { |c| c["hidden"] == true }
    assert_not_empty hidden_commands, "Expected some hidden commands with --all flag"
  end

  test "commands outputs YAML format" do
    output = run_commands_command(["--format=yaml"])
    result = YAML.safe_load(output, permitted_classes: [Symbol], aliases: true)

    assert_kind_of Hash, result
    assert result.key?("schema_version") || result.key?(:schema_version)
    assert result.key?("commands") || result.key?(:commands)
  end

  test "commands outputs human-readable table format" do
    output = run_commands_command(["--format=table"])

    assert_match(/routes/, output)
    assert_match(/db:migrate/, output)
  end

  test "commands command has proper help" do
    output = rails("commands", ["--help"])

    assert_match(/--format/, output)
    assert_match(/--all/, output)
    assert_match(/--no-rake/, output)
    assert_match(/--grep/, output)
    assert_match(/--names-only/, output)
  end

  test "commands filters by grep pattern" do
    output = run_commands_command(["--format=json", "--grep=routes"])
    result = JSON.parse(output)

    assert_not_empty result["commands"], "Expected some commands matching 'routes'"
    result["commands"].each do |cmd|
      assert_match(/routes/i, cmd["full_name"], "Expected all commands to match 'routes'")
    end
  end

  test "commands grep is case-insensitive" do
    output = run_commands_command(["--format=json", "--grep=ROUTES"])
    result = JSON.parse(output)

    routes_command = result["commands"].find { |c| c["full_name"] == "routes" }
    assert_not_nil routes_command, "Expected to find 'routes' with uppercase grep"
  end

  test "commands grep filters both Thor and Rake commands" do
    output = run_commands_command(["--format=json", "--grep=db"])
    result = JSON.parse(output)

    rake_commands = result["commands"].select { |c| c["kind"] == "rake" }

    assert_not_empty rake_commands, "Expected some rake db commands"
    assert(result["commands"].all? { |c| c["full_name"].downcase.include?("db") })
  end

  test "commands names-only outputs just command names as JSON array" do
    output = run_commands_command(["--format=json", "--names-only"])
    result = JSON.parse(output)

    assert_kind_of Array, result
    assert_not_empty result
    assert result.all? { |name| name.is_a?(String) }
    assert_includes result, "routes"
    assert_includes result, "db:migrate"
  end

  test "commands names-only outputs one name per line in table format" do
    output = run_commands_command(["--format=table", "--names-only"])

    assert_match(/^routes$/, output)
    assert_match(/^db:migrate$/, output)
    assert_no_match(/KIND/, output)
  end

  test "commands names-only with grep returns filtered names" do
    output = run_commands_command(["--format=json", "--names-only", "--grep=migrate"])
    result = JSON.parse(output)

    assert_kind_of Array, result
    assert(result.all? { |name| name.downcase.include?("migrate") })
  end

  test "each command has required fields" do
    output = run_commands_command(["--format=json"])
    result = JSON.parse(output)

    result["commands"].each do |command|
      assert command.key?("kind"), "Command missing 'kind': #{command.inspect}"
      assert command.key?("full_name"), "Command missing 'full_name': #{command.inspect}"
      assert %w[thor rake].include?(command["kind"]), "Invalid kind: #{command["kind"]}"
    end
  end

  test "commands full_name can be used directly with bin/rails" do
    output = run_commands_command(["--format=json"])
    result = JSON.parse(output)

    routes_command = result["commands"].find { |c| c["full_name"] == "routes" }
    assert_not_nil routes_command

    routes_output = rails(routes_command["full_name"], ["--help"])
    assert_match(/routes/, routes_output)
  end

  private
    def run_commands_command(args = [])
      rails "commands", args
    end
end
