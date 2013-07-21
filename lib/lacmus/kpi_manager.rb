require_relative 'settings'

module Lacmus
	module KpiManager

		def self.mark(kpi, experiment_id)
			Lacmus.fast_storage.zincrby experiment_key(experiment_id), 1, kpi.to_s
		end

		def self.reset_all(experiment_id)
			Lacmus.fast_storage.del experiment_key(experiment_id)
		end

		def self.all_kpis_for_experiment(experiment_id)
			Lacmus.fast_storage.zrange experiment_key(experiment_id), 0, -1
		end

		def self.experiment_key(experiment_id)
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-kpis-#{experiment_id.to_s}"
		end
	end
end