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

	# Generate a new unique user id for the given user.
	# The counter will reset itself when it reaches 10M.
	#
	# @return [ Integer ] The new user id
	#
	def generate_user_id
		new_user_id = fast_storage.incr user_id_key
		if new_user_id > 100000000
			fast_storage.set(user_id_key, 1)
		end
		new_user_id
	end

	def restart_user_ids_counter
		fast_storage.del user_id_key
	end

	def user_id_key
		"#{LACMUS_PREFIX}-tmp-uid"
	end
end