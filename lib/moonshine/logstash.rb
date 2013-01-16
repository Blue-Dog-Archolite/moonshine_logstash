module Moonshine
  module Logstash
    def logstash_shipper(options = {})
      base_operations(options)

      service "logstash-shipper",
        :ensure => :running,
        :enable => [:enable_on_boot],
        :require => [
          file("/etc/init.d/logstash-shipper"),
          #          user('rails'), group('rails'),
        ]
    end

    def logstash_indexer(options = {})
      base_operations(options)

      service "logstash-indexer",
        :ensure => :running,
        :enable => [:enable_on_boot],
        :require => [
          file("/etc/init.d/logstash-indexer"),
          #          user('rails'), group('rails'),
        ]
    end


    def logstash(options = {})
      logstash_shipper(options)
      logstash_indexer(options)

      service "logstash-combined",
        :ensure => :running,
        :enable => [:enable_on_boot],
        :require => [
          file("/etc/init.d/logstash-combined"),
          #          user('rails'), group('rails'),
        ]
     end

    def base_operations(options = {})
      puts '*'*100
      puts "Base Operations"
      puts "installed == #{@installed}"
      puts '*'*100

      return if @installed
      @options = options
      @installed ||= true

      verify_dependencies
      set_updatedb
      install_grok
      download_logstash
      create_config_files(options)

      install_all_services
    end


    private
    def verify_dependencies
      java_package = configuration[:logstash][:java_runtime] if configuration[:logstash] && configuration[:logstash][:java_runtime]
      java_package = "openjdk-6-jdk"
      package 'wget', :ensure => :installed
      package java_package, :ensure => :installed
      end

    def set_updatedb
      cron "make sure updatedb is running nightly",
        :command => "updatedb",
        :user => 'root',
        :hour => 0,
        :minute => 0,
        :weekday => 0
    end

    def install_grok
      exec 'install grok',
        :command => ['wget -O grok.deb http://semicomplete.googlecode.com/files/grok_1.20101030.3088_amd64.deb',
                     'dpkg -i grok.deb'].join(' && '),
                     :unless => 'test -f /usr/bin/grok',
                     :cwd => '/tmp'

      gem 'jls-grok'
    end

    def download_logstash
      puts '*'*100
      puts "download logstash"
      puts '*'*100

      file '/usr/local/bin/logstash', :ensure => :directory
      file '/usr/local/bin/logstash/data', :ensure => :directory
      file '/usr/local/share/logstash', :ensure => :directory
      file '/usr/local/share/logstash/data', :ensure => :directory

      exec 'download logstash',
        :command =>  'wget -O logstash-1.1.5.jar http://semicomplete.com/files/logstash/logstash-1.1.5-monolithic.jar',
        :unless => 'locate -c logstash-1.1.5.jar',
        :cwd => '/usr/local/bin/logstash/'

      puts `ll /usr/local/bin/logstash/logstash-1.1.5.jar`
    end

    #
    # Create config files from each of the templates configured below.
    #
    def create_config_files(options)
      puts '*'*100
      puts "config files"
      puts '*'*100

      # Ensure the logstash configuration directory exists.
      file '/etc/logstash', :ensure => :directory
      file '/etc/logstash/conf', :ensure => :directory
      file '/etc/logstash/conf/grok_patterns/', :ensure => :directory
      # Copy the default logstash config file
      #    create_file_from_template '/etc/default/logstash', 'default_logstash.erb'

      # Create logstash config files
      (logstash_config_files + grok_config_files).flatten.each do |logstash_config_file|
        if should_use_local_config_file(logstash_config_file) && local_config_file_exists(logstash_config_file)
          use_local_config_file(logstash_config_file)
        else
          create_file_from_template(logstash_config_path(logstash_config_file), config_file_template(logstash_config_file))
        end
      end
    end

    # The full list of config files that will be made available to logstash.
    def logstash_config_files
      %w(redis-indexer.conf redis-shipper.conf indexer-filter.conf redis-combined.conf)
    end

    def logstash_service_files
      %w{init-combined init-indexer init-shipper}
    end

    def grok_config_files
      %w{grok-patterns linux-syslog ruby}.collect{|a| "grok_patterns/#{a}"}
    end

    #
    # Convenience method to create files from templates.
    #
    def create_file_from_template(file_name, template_path, mode = '644')
      file file_name,
        :ensure => :present,
        :mode => mode,
        :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', template_path), binding)
        end

    #
    # Convenience method to copy an existing (local) config file
    # and use it for logstash.
    #
    def use_local_config_file(config_file, mode = '644')
      file logstash_config_path(config_file),
        :ensure => :present,
        :mode => mode,
        :content => File.read(File.join(deploy_path, 'current', 'logstash', 'conf', config_file))
        end

    #
    # The user that runs the Rails application
    #
    def moonshine_user
      configuration[:user]
    end

    #
    # Path where the Rails application is deployed to.
    #
    def deploy_path
      configuration[:deploy_to]
    end

    #
    # Should +config_file+ be used from the Rails app source tree?
    #
    def should_use_local_config_file(config_file)
      return true if options[:use_my_config_files] == :all
      options[:use_my_config_files] && options[:use_my_config_files].is_a?(Array) && options[:use_my_config_files].include?(config_file)
    end

    #
    # Does +config_file+ exist in the Rails app source tree?
    #
    def local_config_file_exists(config_file)
      File.exists?(File.join(deploy_path, 'current', 'logstash', 'conf', config_file))
    end

    #
    # Template file for +config_file+
    #
    def config_file_template(config_file)
      "#{config_file}.erb"
    end

    #
    # This is where all logstash configuration will be stored on the server.
    #
    def logstash_config_path(config_file)
      File.join('/', 'etc', 'logstash', 'conf', config_file)
    end

    #
    # Shortcut to provided options
    #
    def options
      @options ||= {}
    end

    #
    # Restart logstash servlet container.
    def install_all_services

      @location = "/usr/local/bin/logstash"
      @logstash = "logstash-1.1.5.jar"
      @config_location = "/etc/logstash/conf"
      @grok_config_location = "/etc/logstash/conf/grok_patterns"
      @flags = "agent -f "

      logstash_service_files.each do |service|
        service_name = "logstash-#{service.split('-').last}"
        service_config_file = "redis-#{service.split('-').last}.conf"



        @to_run = "java -jar #{@location}/#{@logstash} #{@flags} #{@config_location}/#{service_config_file}"

        file "/usr/local/bin/#{service_name}",
        :ensure => :present,
        :mode => '755',
        :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', "service.erb"), binding)


        file "/etc/init.d/#{service}",
        :ensure => :present,
        :mode => '755',
        :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', "#{service}.d.erb"), binding)
        end

    end

    def lookupvar(tofind)
      @find_me = "configuration"
      tofind.split('::').each do |s|
        @find_me += "[#{(":"+s).to_sym}]"
      end

      self.instance_eval @find_me
    end

    #
    # Restart logstash servlet container.
    def install_all_services

      puts '*'*100
      puts "Service Install"

      @location = "/usr/local/bin/logstash"
      @logstash = "logstash-1.1.5.jar"
      @config_location = "/etc/logstash/conf"
      @grok_config_location = "/etc/logstash/conf/grok_patterns"
      @flags = "agent -f "

      logstash_service_files.each do |service|
        @service = service
        puts @service

        @service_name = "logstash-#{service.split('-').last}"
        @service_config_file = "redis-#{service.split('-').last}.conf"

        @to_run = "cd #{@location} && java -jar #{@location}/#{@logstash} #{@flags} #{@config_location}/#{@service_config_file} &"

        puts "/usr/local/bin/#{@service_name}"
        file "/usr/local/bin/#{@service_name}",
        :ensure => :present,
        :mode => '755',
        :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', "service.erb"), binding)


        puts "/etc/init.d/#{@service_name}"
        file "/etc/init.d/#{@service_name}",
        :ensure => :present,
        :mode => '755',
        :content => template(File.join(File.dirname(__FILE__), '..', '..', 'templates', "init-template.d.erb"), binding)
        end
      puts '*'*100
    end

    def lookupvar(tofind)
      @find_me = "configuration"
      tofind.split('::').each do |s|
        @find_me += "[#{(":"+s).to_sym}]"
      end

      self.instance_eval @find_me
    end
  end
end
