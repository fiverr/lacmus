require_relative 'fast_storage'
require_relative 'settings'
require_relative 'experiment'
require 'redis'

module Lacmus
	module ExperimentHistory

		# Constants
		KEY_EXPIRE_IN_SECONDS = 7776000 # 3 months

		def self.log_experiment(tmp_user_id, experiment_id, exposed_at)
			experiment_name = Lacmus::Experiment.new(experiment_id).safe_name(true)
p experiment_name
			exposed_at = exposed_at.to_i

			Lacmus.fast_storage.multi do
				Lacmus.fast_storage.zadd key(tmp_user_id), exposed_at, experiment_name
				Lacmus.fast_storage.expire key(tmp_user_id), KEY_EXPIRE_IN_SECONDS
			end
		end

		def self.experiments(tmp_user_id)
			Lacmus.fast_storage.zrange(key(tmp_user_id), 0, -1, :with_scores => true)
		end

		def self.key(tmp_user_id)
			"#{Lacmus.namespace}-exp-history-#{tmp_user_id}"
		end
	end
end