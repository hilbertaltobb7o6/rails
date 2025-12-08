# frozen_string_literal: true

require "rails/command"

module Rails
  module Command
    class CommandsCommand < Base # :nodoc:
      desc "commands", "List all available Rails commands with their options"

      class_option :format, type: :string, aliases: "-f",
        enum: %w[json yaml table], default: "table",
        desc: "Output format (json, yaml, or table)"

      class_option :all, type: :boolean, default: false,
        desc: "Include hidden commands and help subcommands"

      class_option :rake, type: :boolean, default: true,
        desc: "Include Rake tasks"

      class_option :grep, type: :string, aliases: "-g",
        desc: "Filter commands by name (case-insensitive substring match)"

      class_option :names_only, type: :boolean, default: false,
        desc: "Output only command names as a list"

      def perform
        commands = collect_all_commands
        commands = filter_commands(commands)

        if options[:names_only]
          output = format_names_only(commands)
        else
          data = build_commands_data(commands)
          output = format_output(data)
        end

        say output
      end

      private
        def build_commands_data(commands)
          {
            "schema_version" => "1.0",
            "rails_version" => Rails::VERSION::STRING,
            "commands" => commands
          }
        end

        def collect_all_commands
          commands = collect_thor_commands
          commands += collect_rake_tasks if options[:rake]
          commands.sort_by { |c| c["full_name"] }
        end

        def filter_commands(commands)
          commands = filter_help_commands(commands) unless options[:all]
          commands = filter_by_grep(commands) if options[:grep].present?
          commands
        end

        def filter_help_commands(commands)
          commands.reject { |cmd| cmd["full_name"].end_with?(":help") }
        end

        def filter_by_grep(commands)
          pattern = options[:grep].downcase
          commands.select { |cmd| cmd["full_name"].downcase.include?(pattern) }
        end

        def collect_thor_commands
          Rails::Command.send(:lookup!)

          Rails::Command.subclasses.flat_map do |klass|
            next if skip_command_class?(klass)

            klass.all_commands.filter_map do |name, cmd|
              next if !options[:all] && cmd.hidden?

              build_thor_command_hash(klass, name, cmd)
            end
          end.compact
        end

        def skip_command_class?(klass)
          return true if klass == Rails::Command::RakeCommand
          return true if !options[:all] && Rails::Command.hidden_commands.include?(klass)
          false
        end

        def build_thor_command_hash(klass, name, cmd)
          full_name = klass.send(:namespaced_name, name)

          {
            "kind" => "thor",
            "full_name" => full_name,
            "namespace" => klass.namespace,
            "command" => name.to_s,
            "description" => cmd.description.presence || klass.class_usage.to_s.lines.first&.strip,
            "hidden" => cmd.hidden? || Rails::Command.hidden_commands.include?(klass),
            "options" => build_options_array(klass, cmd)
          }.compact
        end

        def build_options_array(klass, cmd)
          all_options = klass.class_options.merge(cmd.options || {})

          all_options.filter_map do |name, opt|
            next if opt.hide

            {
              "name" => "--#{name}",
              "aliases" => opt.aliases.presence,
              "type" => opt.type.to_s,
              "required" => opt.required? || nil,
              "description" => opt.description,
              "default" => serialize_default(opt.default),
              "enum" => opt.enum
            }.compact
          end
        end

        def serialize_default(value)
          case value
          when nil, false then nil
          when true then true
          else value
          end
        end

        def collect_rake_tasks
          require "rails/commands/rake/rake_command"

          Rails::Command::RakeCommand.send(:rake_tasks).filter_map do |task|
            next unless task.comment

            {
              "kind" => "rake",
              "full_name" => task.name,
              "namespace" => "rake",
              "description" => task.comment,
              "arguments" => task.arg_names.map(&:to_s).presence,
              "source" => task.locations.first
            }.compact
          end
        rescue LoadError, RuntimeError
          []
        end

        def format_names_only(commands)
          names = commands.map { |c| c["full_name"] }

          case options[:format]
          when "json"
            require "json"
            JSON.pretty_generate(names)
          when "yaml"
            require "yaml"
            names.to_yaml
          when "table"
            names.join("\n")
          end
        end

        def format_output(data)
          case options[:format]
          when "json"
            require "json"
            JSON.pretty_generate(data)
          when "yaml"
            require "yaml"
            data.to_yaml
          when "table"
            format_as_table(data)
          end
        end

        def format_as_table(data)
          commands = data["commands"]
          return "No commands found." if commands.empty?

          lines = []
          lines << "%-6s %-40s %s" % ["KIND", "COMMAND", "DESCRIPTION"]
          lines << "-" * 80

          commands.each do |cmd|
            description = cmd["description"].to_s.truncate(35)
            lines << "%-6s %-40s %s" % [cmd["kind"], cmd["full_name"], description]
          end

          lines.join("\n")
        end
    end
  end
end
