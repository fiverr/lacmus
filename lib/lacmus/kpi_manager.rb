require_relative 'settings'

module Lacmus
	module KpiManager

		def self.mark(kpi, experiment_id)
			Lacmus.fast_storage.zincrby key(experiment_id), 1, kpi.to_s
		end

		def self.reset_all(experiment_id)
			Lacmus.fast_storage.del key(experiment_id)
		end

		def self.all_kpis_for_experiment(experiment_id)
			Lacmus.fast_storage.zrange(key(experiment_id), 0, -1, :with_scores => true)
		end

		def self.key(experiment_id)
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-kpis-#{experiment_id.to_s}"
		end
	end
end