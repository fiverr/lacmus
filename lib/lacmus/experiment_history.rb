require 'lacmus'
require 'lacmus/experiment'
require 'redis'

module Lacmus
	module ExperimentHistory
		extend self

		# Constants
		KEY_EXPIRE_IN_SECONDS = 2592000 # 1 month

		def add(user_id, experiment_id, is_control = false)
			Lacmus.fast_storage.multi do
				Lacmus.fast_storage.zadd key(user_id, is_control), Time.now.utc.to_i, experiment_id
				Lacmus.fast_storage.expire key(user_id, is_control), KEY_EXPIRE_IN_SECONDS
			end
		end

		def all(user_id)
			control_group 	 = for_group(user_id, true)
			experiment_group = for_group(user_id, false)

			control_group + experiment_group
		end

		def clear(user_id)
			Lacmus.fast_storage.del key(user_id)
			Lacmus.fast_storage.del key(user_id, true)
		end

		def for_group(user_id, is_control)
			history = []
			data = Lacmus.fast_storage.zrange(key(user_id, is_control), 0, -1, :with_scores => true)
			data.each do |item|
				experiment_id, exposed_at = item[0], item[1]
				history << ExperimentHistoryItem.new(user_id, experiment_id, exposed_at, is_control)
			end
			history
		end

		def for_control_group(user_id)
			for_group(user_id, true)
		end

		def for_experiment_group(user_id)
			for_group(user_id, false)
		end

		def key(user_id, is_control = false)
			"#{LACMUS_PREFIX}-exp-history-#{user_id}-#{is_control}"
		end

	end # of ExperimentHistory
end # of Lacmus