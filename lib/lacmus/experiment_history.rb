require 'lacmus'
require 'lacmus/experiment'
require 'redis'

module Lacmus
	module ExperimentHistory
		extend self

		# Constants
		KEY_EXPIRE_IN_SECONDS = 2592000 # 1 month

		def log_experiment(user_id, experiment_id)
			Lacmus.fast_storage.multi do
				Lacmus.fast_storage.zadd key(user_id), Time.now.to_i, experiment_id
				Lacmus.fast_storage.expire key(user_id), KEY_EXPIRE_IN_SECONDS
			end
		end

		def experiments(user_id)
			history_items = []
			history_data = Lacmus.fast_storage.zrange(key(user_id), 0, -1, :with_scores => true)
			history_data.each do |history_item|
				experiment_id, exposed_at = history_item[0], history_item[1]
				history_items << ExperimentHistoryItem.new(user_id, experiment_id, exposed_at)
			end
			history_items
		end

		def self.key(user_id)
			"#{LACMUS_PREFIX}-exp-history-#{user_id}"
		end
	end
end