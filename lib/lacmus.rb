require 'yaml'
require 'lacmus/version'
require 'lacmus/settings'
require 'lacmus/lab'
require 'lacmus/slot_machine'
require 'lacmus/experiment'
require 'lacmus/experiment_history'

module Lacmus
	extend self

	# Constants
	LACMUS_PREFIX = "lcms-#{Settings.env_name}"

	# Class Variables
	@@settings = Settings.load!
	@@fast_engine = nil

	def fast_storage
		@@fast_engine ||= Redis.new(@@settings['fast_storage'])
	end

	# generate a unique temporary user id to use for every user
	# this allows us to suppot non-logged in users 
	# the counter will reset itself when it reaches 10M
	def generate_tmp_user_id
		index = fast_storage.incr tmp_user_id_key
		fast_storage.set tmp_user_id_key, 1 if index > 100000000
		index
	end

	def restart_temp_user_ids
		fast_storage.del tmp_user_id_key
	end

	def tmp_user_id_key
		"#{LACMUS_PREFIX}-tmp-uid"
	end
end