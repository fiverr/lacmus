require_relative "settings"
require 'yaml'

# initializes the fast storage, in our case - redis
module Lacmus
	module FastStorage

		@@settings = YAML.load(File.open("#{Lacmus::Settings::ROOT}/config/lacmus.yml"))[Lacmus::Settings::ENV]
		@@redis = nil 

		def self.instance
			@@redis ||= Redis.new(@@settings['fast_storage'])
		end
	end
end