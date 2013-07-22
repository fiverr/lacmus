module Lacmus
	module Helper
		def simple_experiment(experiment_id, control_version, experiment_version)
			Lacmus::Lab.simple_experiment(experiment_id, control_version, experiment_version, {:cookies => cookies})
		end
	end
end

ActionController::Base.send(:include, Lacmus::Helper) if $has_rails
