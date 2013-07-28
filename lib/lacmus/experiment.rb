require_relative 'settings'
require_relative 'fast_storage'

module Lacmus
	class Experiment

		# Accessors
		attr_accessor :id
		attr_accessor :name
		attr_accessor :description
		attr_accessor :start_time
		attr_accessor	:end_time
		attr_accessor	:status
		attr_accessor :screenshot_url
		attr_accessor :errors

		attr_reader :control_kpis
		attr_reader :experiment_kpis
		attr_reader :control_analytics
		attr_reader :experiment_analytics

		def initialize(value)
			if value.is_a?(Hash)
				experiment = value
				id = experiment[:experiment_id]
			else
				experiment = Lacmus::SlotMachine.find_experiment(value.to_i)
				id = value
			end

			@id 									= id
			@status 							= experiment[:status]
			@name 								= experiment[:name]
			@description 					= experiment[:description]
			@screenshot_url 			= experiment[:screenshot_url]
			@start_time 					= Time.at(experiment[:start_time_as_int]) if experiment[:start_time_as_int]
			@end_time 						= Time.at(experiment[:end_time_as_int]) if experiment[:end_time_as_int]
			@control_kpis 				= load_experiment_kpis(true) || {}
			@experiment_kpis 			= load_experiment_kpis || {}
			@control_analytics 		= load_experiment_analytics(true) || {}
			@experiment_analytics = load_experiment_analytics || {}
			@errors = []
		end
	
		def available_kpis
			@control_kpis.merge(@experiment_kpis).keys
		end

		def load_experiment_kpis(is_control = false)
			kpis_hash = {}
			kpis = Lacmus.fast_storage.zrange(self.class.kpi_key(@id, is_control), 0, -1, :with_scores => true)
			kpis.each do |kpi_array|
				kpis_hash[kpi_array[0]] = kpi_array[1]
			end
			kpis_hash	
		end

		def load_experiment_analytics(is_control = false)
			{exposures: (Lacmus.fast_storage.get self.class.exposure_key(@id, is_control))}
		end

		def safe_name(include_id = false)
			safe_name = name.gsub(' ', '_').downcase
			if include_id
				safe_name += "_#{id}"
			end
			safe_name
		end

		def nuke
			self.class.nuke_experiment(@id)
		end

		def save
			original_experiment = Lacmus::SlotMachine.get_experiment_from(@status, @id)
			metadata = {
				:name => @name, 
				:description => @description,
				:screenshot_url => @screenshot_url
			}

			original_experiment.merge!(metadata)
			id = original_experiment[:experiment_id]
			
			Lacmus.fast_storage.multi do
				Lacmus.fast_storage.zremrangebyscore list_key_by_type(original_experiment[:status]), id, id
				Lacmus.fast_storage.zadd list_key_by_type(original_experiment[:status]), id, Marshal.dump(original_experiment)
			end
		end

		def self.nuke_experiment(experiment_id)
			Lacmus.fast_storage.multi do
				Lacmus.fast_storage.del kpi_key(experiment_id)
				Lacmus.fast_storage.del kpi_key(experiment_id, true)
				Lacmus.fast_storage.del exposure_key(experiment_id)
				Lacmus.fast_storage.del exposure_key(experiment_id, true)
			end			
		end

		def self.mark_kpi!(kpi, experiment_ids, is_control = false)
			experiment_ids.each do |experiment_id|
				if is_control
					mark_control_group_kpi(kpi, experiment_id)
				else
					mark_experiment_group_kpi(kpi, experiment_id)
				end
			end
		end

		def self.mark_control_group_kpi(kpi, experiment_id)
			Lacmus.fast_storage.zincrby kpi_key(experiment_id, true), 1, kpi.to_s
		end

		def self.mark_experiment_group_kpi(kpi, experiment_id)
			Lacmus.fast_storage.zincrby kpi_key(experiment_id, false), 1, kpi.to_s
		end

		def self.track_experiment_exposure(experiment_id, is_control = false)
			if is_control
				Lacmus.fast_storage.incr exposure_key(experiment_id, true)
			else
				Lacmus.fast_storage.incr exposure_key(experiment_id)
			end
		end

		def control_conversion(kpi)
			return 0 if !control_analytics || control_analytics[:exposures].to_i == 0
			return 0 if !control_kpis || control_kpis[kpi].to_i == 0
			(control_kpis[kpi].to_f / control_analytics[:exposures].to_f) * 100
		end

		def experiment_conversion(kpi)
			return 0 if !experiment_analytics || experiment_analytics[:exposures].to_i == 0
			return 0 if !experiment_kpis || experiment_kpis[kpi].to_i == 0
			(experiment_kpis[kpi].to_f / experiment_analytics[:exposures].to_f) * 100
		end

		def enough_participants_tested?(kpi)
			#conversion rate for group 1
			c1 = control_conversion(kpi).to_i
			c2 = experiment_conversion(kpi).to_i
			# average conversion rate
			ac = ((c1+c2)/2).to_i
			# required number of participants in test group
			participants_needed = (16*ac*(1-ac))/((c1-c2)^2)

			total_participants = experiment_analytics[:exposures].to_i + control_analytics[:exposures].to_i
			# if there aren't enogh participants, return false
			return (participants_needed < total_participants)
		end

		private

		def self.is_control_group?(experiment_id)
			experiment_id == 0
		end

		def list_key_by_type(list)
			Lacmus::SlotMachine.list_key_by_type(list)
		end
	
		def self.all_from(list)
			experiments = []
			experiments_as_hash = Lacmus::SlotMachine.get_experiments(list)
			experiments_as_hash.each do |exp_hash|
				experiments << Experiment.new(exp_hash)
			end
			experiments
		end

		def self.kpi_key(experiment_id, is_control = false)
			"#{Lacmus.namespace}-#{is_control}-kpis-#{experiment_id.to_s}"
		end

		def self.exposure_key(experiment_id, is_control = false)
			"#{Lacmus.namespace}-#{is_control}-counter-#{experiment_id.to_s}"
		end

	end # of Experiment

	class ExperimentHistoryItem < Experiment
		attr_accessor :user_tmp_id
		attr_accessor :exposed_at

		def initialize(user_tmp_id, experiment_id, exposed_at)
			@user_tmp_id = user_tmp_id
			@exposed_at  = exposed_at
			super(experiment_id)
		end

	end # of ExperimentHistoryItem
end # of Lacmus