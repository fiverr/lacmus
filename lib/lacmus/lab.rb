module Lacmus
	module Lab
		
		# if 
		def self.render_default(experiment_id, &block)
			return unless should_render_default?(experiment_id)
			if Lacmus::Experiment.control_group?
				Lacmus::Experiment.track_exposure(experiment_id)
			end
			yield(block)
		end

		def self.should_render_default?(experiment_id)
			group = Lacmus::Experiment.get_group
			return true if group.zero?
			return true if !Lacmus::Experiment.experiment_active?(experiment_id)
			return false
		end

		def self.should_render_experiment?(experiment_id)
			group = Lacmus::Experiment.get_group
			return false if group.zero?
			return false if !Lacmus::Experiment.experiment_active?(experiment_id)
			return true
		end

		def self.render_experiment(experiment_id, &block)
			return unless should_render_experiment?(experiment_id)
			Lacmus::Experiment.track_exposure(experiment_id)
			yield(block)
		end

		def self.simple_experiment(experiment_id, default_results, experiment_result)
			if should_render_experiment?(experiment_id)
				Lacmus::Experiment.track_exposure(experiment_id)
				return experiment_result	
			end

			if Lacmus::Experiment.control_group?
				Lacmus::Experiment.track_exposure(experiment_id)
			end

			default_results
		end

		def self.experiment_cache_key
			Lacmus::Experiment.get_group.to_s
		end

	end
end