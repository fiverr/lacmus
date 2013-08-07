require_relative "settings"
require 'yaml'

# initializes the fast storage, in our case - redis
module Lacmus
	module FastStorage
		extend self

		@@settings = YAML.load(File.open("#{Lacmus::Settings::ROOT}/config/lacmus.yml"))[Lacmus::Settings::ENV]
		@@redis = nil 

		def instance
			@@redis ||= Redis.new(@@settings['fast_storage'])
		end
	end
end