require_relative "settings"

module Lacmus
	module Utils

		@@engine = nil

		# generate a unique temporary user id to use for every user
		# this allows us to suppot non-logged in users 
		# the counter will reset itself when it reaches 10M
		def self.generate_tmp_user_id
			index = Lacmus.fast_storage.incr tmp_user_id_key
			Lacmus.fast_storage.set tmp_user_id_key, 1 if index > 100000000
			index
		end

		def self.tmp_user_id_key
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-tmp-uid"
		end

		# picks a group for a given tmp user id
		def self.pick_group(user_id)
			(user_id.to_i % 2).to_i
		end

	end
end