module Kontena
  module Callbacks
    class BeforeDeployConfigurationWizard < Kontena::Callback

      include Kontena::Cli::Common

      matches_commands 'master create'

      def after_load
        command.class_eval do
          option ['--no-prompt'], :flag, "Don't ask questions"
          option ['--skip-auth-provider'], :flag, "Skip auth provider configuration (single user mode)"
          option ['--cloud-master-id'], '[ID]', "Use Kontena Cloud Master ID for auth provider configuration"
        end
      end

      def unless_param(param, &block)
        return if command.respond_to?(param) && !command.send(param).nil?
        return if command.respond_to?("#{param}?".to_sym) && command.send("#{param}?".to_sym)
        yield
      end

      # Scans config server names and returns default-2 if default exists,
      # default-3 if default-2 exists, etc.
      def next_default_name
        last_default = config.servers.map(&:name).select{ |n| n =~ /kontena\-master(?:\-\d+)?$/ }.sort.last
        return "kontena-master" unless last_default
        unless last_default =~ /\d$/
          last_default << "-1"
        end
        last_default.succ
      end

      def login_to_kontena
        if kontena_auth?
          return true if cloud_client.authentication_ok?(kontena_account.userinfo_endpoint)
        end
        puts
        puts "You don't seem to be logged in to Kontena Cloud"
        puts
        Kontena.run("cloud login --verbose")
        cloud_client.authentication_ok?(kontena_account.userinfo_endpoint)
      end

      def create_cloud_master
        master_id = nil
        begin
          spinner "Registering a new master '#{command.name}' to Kontena Cloud" do
            master_id = Kontena.run("cloud master add --return #{command.name}", returning: :result)
          end
        rescue SystemExit
        end
        if master_id.to_s =~ /^[0-9a-f]{16,32}$/
          master_id
        else
          abort 'Cloud Master registration failed'
        end
      end

      def before
        unless_param(:name) do
          if command.no_prompt?
            command.name = next_default_name
          else
            command.name = prompt.ask("Enter a name for this Kontena Master: ", default: next_default_name, required: true) do |q|
              q.validate /^[a-z0-9\_\-\.]+$/, 'Name should only include lower case letters, numbers and -._, example: "master-4"'
            end
          end
        end

        unless_param(:skip_auth_provider) do
          if command.no_prompt?
            command.cloud_master_id ||= create_cloud_master
          elsif command.cloud_master_id.nil?
            answer = prompt.select("Select OAuth2 authentication provider: ") do |menu|
              menu.choice 'Kontena Cloud (recommended)', :kontena_new
              menu.choice 'Custom', :custom
              menu.choice 'None (single user mode)', :none
            end
            case answer
            when :kontena_new
              login_to_kontena || abort('You must login to Kontena Cloud')
              command.cloud_master_id = create_cloud_master
              command.skip_auth_provider = false
            when :custom
              puts
              puts 'Learn how to configure custom user authentication provider after installation at: www.kontena.io/docs/configuring-custom-auth-provider'
              puts
              command.cloud_master_id = nil
              command.skip_auth_provider = true
            when :none
              puts
              puts "You have selected to use Kontena Master in single user mode. You can configure an authentication provider later. For more information, see here: www.kontena.io/docs/configuring-custom-auth-provider"
              puts
              command.cloud_master_id = nil
              command.skip_auth_provider = true
            else
              abort 'Should never be here'
            end
          end
        end
        true
      end
    end
  end
end

