# encoding: utf-8
module Lacmus
	module AlternativeUser
		extend self

		def get_user_id(alternative_user_id)
			Lacmus.fast_storage.get key(alternative_user_id)
		end

		def set_user_id(user_id, alternative_user_id)
			Lacmus.fast_storage.setex key(alternative_user_id), ttl, user_id
		end

		private

		def key(alternative_user_id)
			"#{LACMUS_PREFIX}-#{alternative_user_id}"
		end

		def ttl
			Lab::COOKIE_AGE_IN_SECONDS
		end

	end
end