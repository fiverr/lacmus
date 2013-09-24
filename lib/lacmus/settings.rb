# encoding: utf-8
module Lacmus
  # Lacmus settings are defined using the lacmus.yml file.
  # Lacmus is using redis as the database engine, so it's
  # a must to configure the redis connection first.
  #
  # @example Example for lacmus.yml file (development environment)
  #
  #   development:
  #     fast_storage:
  #       host: 127.0.0.1
  #       port: 6379
  #
  module Settings
    extend self

    attr_accessor :all

    # Loads all the settings from the lacmus.yml file and define a method
    # for each key.
    #
    # @example
    #   Lacmus::Settings.load! # => {"fast_storage"=>{"host"=>"127.0.0.1", "port"=>6379}}
    #   Lacmus::Settings.fast_storage # => {"host"=>"127.0.0.1", "port"=>6379}
    #   Lacmus::Settings.all # => {"fast_storage"=>{"host"=>"127.0.0.1", "port"=>6379}}
    #
    # @return [ ActiveSupport::HashWithIndifferentAccess ] All the settings with indifference access,
    #   making keys available both as strings and symbols.
    # 
    def load!
      data = YAML.load(File.open("#{root}/config/lacmus.yml"))[env_name]
      data.keys.each do |key|
        self.class.instance_eval do
          define_method(key) do
            data[key]
          end
        end
      end
      self.all = ActiveSupport::HashWithIndifferentAccess.new(data)
    end

    # Returns the environment we're running under.
    # If not available - development will be returned.
    #
    # @return [ String ] The environment name
    #
    def env_name
      return Lacmus::ENV if defined?(Lacmus::ENV)
      return Rails.env   if defined?(Rails)
      return 'development'
    end

    # Returns the root of the project we're running under.
    #
    # @example
    #   Lacmus::Settings.root # => '/home/admin'
    #
    # @return [ String ] The root location
    #
    def root
      return Lacmus::ROOT if defined?(Lacmus::ROOT)
      return Rails.root   if defined?(Rails) && Rails.root
      return Dir.pwd
    end

    # Convenience method to check if we're running under
    # a Rails application.
    #
    # @return [ Boolean ] True if running under rails, false otherwise.
    # 
    def running_under_rails?
      defined?(Rails)
    end

    load!

  end # of Settings
end # of Lacmus