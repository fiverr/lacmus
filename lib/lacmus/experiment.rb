require 'active_support/core_ext/hash/indifferent_access'

require 'lacmus'
require 'lacmus/slot_machine'
require 'lacmus/settings'

module Lacmus
	class Experiment

		# Raised when trying to initialize an experiment object
		# with somethong other than a Hash.
		class InvalidInitValue < StandardError; end

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

		def initialize(options = {})
			raise InvalidInitValue unless options.is_a?(Hash)
			options = ActiveSupport::HashWithIndifferentAccess.new(options)

			@id 									= options[:id]
			@status 							= options[:status]
			@name 								= options[:name]
			@description 					= options[:description]
			@screenshot_url 			= options[:screenshot_url]
			@start_time 					= options[:start_time]
			@end_time 						= options[:end_time]
			@control_kpis 				= load_experiment_kpis(true)
			@experiment_kpis 			= load_experiment_kpis
			@control_analytics 		= load_experiment_analytics(true)
			@experiment_analytics = load_experiment_analytics
			@errors 							= []
		end

		def self.create!(options = {})
			attrs = {
				id: 		generate_experiment_id,
				status: :pending
			}.merge(options)

			exp_obj = new(attrs)
			exp_obj.save
			exp_obj.add_to_list(:pending)
			exp_obj
		end

		def add_to_list(list)
			if list.to_sym == :active
				available_slot_id = SlotMachine.find_available_slot
				return false if available_slot_id.nil?
				SlotMachine.place_experiment_in_slot(@id, available_slot_id)
			end

			@status = list.to_sym
			save

			Lacmus.fast_storage.zadd self.class.list_key_by_type(list), @id, Marshal.dump(experiment_as_hash)
			return true
		end

		# Removes an experiment from the given list.
		#
		# @param [ Symbol, String ] list The list to remove from.
		# 	Available options: :pending, :active, :completed
		#
		def remove_from_list(list)
			if list.to_sym == :active
				SlotMachine.remove_experiment_from_slot(@id)
			end
			Lacmus.fast_storage.zremrangebyscore self.class.list_key_by_type(list), @id, @id
		end	

		# Move experiment from one list to another.
		# Valid list types - :pending, :active, :completed
		#
		# @return [ Boolean ] true on success, false if experiment not found
		#
		def move_to_list(list)
			current_list = @status

			if current_list == :pending && list == :active
				@start_time = Time.now.utc
			end

			if current_list == :completed && list == :active
				@end_time = nil
			end

			if current_list == :active && list == :completed
				@end_time = Time.now.utc
			end

			result = add_to_list(list)
			return false unless result

			remove_from_list(current_list)
			return true
		end

		def save
			Lacmus.fast_storage.multi do
				Lacmus.fast_storage.zremrangebyscore self.class.list_key_by_type(@status), @id, @id
				Lacmus.fast_storage.zadd self.class.list_key_by_type(@status), @id, Marshal.dump(experiment_as_hash)
			end
		end

		# Activate an exeprtiment.
		# 
		# @return [ Boolean ] true on success, false on failure.
		#
		def activate!
			move_to_list(:active)
		end

		# Removes an experiment from the active experiments list
		# and clears it's slot.
		#
		def deactivate!
			SlotMachine.remove_experiment_from_slot(@id)
			move_to_list(:completed)
		end

		# Permanently deletes an experiment, removing the experiment
		# from it's current list (active/pending/completed).
		#
		# @param [ Integer ] experiment_id The id of the experiment.
		#
		def self.destroy(experiment_id)
			experiment = find(experiment_id)
			experiment.remove_from_list(experiment.status)
			nuke_experiment(experiment_id)
		end

		def self.find(experiment_id)
			experiment = nil
			[:active, :pending, :completed].each do |list|
				break if experiment
				experiment = find_in_list(experiment_id, list)
			end
			experiment
		end

		def self.find_in_list(experiment_id, list)
			experiment = Lacmus.fast_storage.zrangebyscore list_key_by_type(list), experiment_id, experiment_id
			return nil if experiment.nil? || experiment.empty?
			experiment_hash = Marshal.load(experiment.first)
			new(experiment_hash)
		end

		def self.find_all_in_list(list)
			experiments_array 	= []
			experiments_in_list = Lacmus.fast_storage.zrange list_key_by_type(list), 0, -1
			experiments_in_list.each do |experiment|
				experiment_hash = Marshal.load(experiment)
				experiments_array << new(experiment_hash)
			end
			experiments_array
		end

		def experiment_as_hash
			attrs_hash = {}
			instance_variables.each do |var|
				key = var.to_s.delete('@')
				attrs_hash[key] = instance_variable_get(var)
			end
			attrs_hash
		end

		def available_kpis
			@control_kpis.merge(@experiment_kpis).keys
		end

		def active?
			self.class.active?(@id)
		end

		def self.active?(experiment_id)
			SlotMachine.experiment_slot_ids.include?(experiment_id.to_i)
		end

		def self.special_experiment_id?(experiment_id)
			[0, -1].include?(experiment_id)
		end

		def load_experiment_kpis(is_control = false)
			return {} if self.class.special_experiment_id?(@id)

			kpis_hash = {}
			kpis = Lacmus.fast_storage.zrange(self.class.kpi_key(@id, is_control), 0, -1, :with_scores => true)
			kpis.each do |kpi_array|
				kpis_hash[kpi_array[0]] = kpi_array[1]
			end
			ActiveSupport::HashWithIndifferentAccess.new(kpis_hash)
		end

		def load_experiment_analytics(is_control = false)
			return {} if self.class.special_experiment_id?(@id)

			analytics_hash = {
				exposures: Lacmus.fast_storage.get(self.class.exposure_key(@id, is_control))
			}
			ActiveSupport::HashWithIndifferentAccess.new(analytics_hash)
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

		def self.set_experiment_kpis(experiment_id, kpis = {})
			return if kpis.empty?
			kpis.keys.each do |kpi_name|
				Lacmus.fast_storage.zincrby kpi_key(experiment_id, false), kpis[kpi_name], kpi_name
			end
		end

		def self.set_control_kpis(experiment_id, kpis = {})
			return if kpis.empty?
			kpis.keys.each do |kpi_name|
				Lacmus.fast_storage.zincrby kpi_key(experiment_id, true), kpis[kpi_name], kpi_name
			end
		end

		def self.set_counter(experiment_id, counter_name, control_group, value)

		end

		def self.track_experiment_exposure(experiment_id, is_control = false)
			if is_control
				Lacmus.fast_storage.incr exposure_key(experiment_id, true)
			else
				Lacmus.fast_storage.incr exposure_key(experiment_id)
			end
		end

		def control_conversion(kpi)
			return 0 if control_analytics[:exposures].to_i == 0
			return 0 if control_kpis[kpi].to_i == 0
			(control_kpis[kpi].to_f / control_analytics[:exposures].to_f) * 100
		end

		def experiment_conversion(kpi)
			return 0 if experiment_analytics[:exposures].to_i == 0
			return 0 if experiment_kpis[kpi].to_i == 0
			(experiment_kpis[kpi].to_f / experiment_analytics[:exposures].to_f) * 100
		end

		def required_participants_needed_for(kpi)
			c1 = control_conversion(kpi).to_f / 100.0
			c2 = experiment_conversion(kpi).to_f / 100.0
			# average conversion rate
			ac = ((c1+c2)/2.0)
			# required number of participants in test group - normalized
			(16*ac*(1-ac))/((c1-c2)*(c1-c2))
		end

		def experiment_progress(kpi)
			total_required = required_participants_needed_for(kpi).to_i
			return 100 if experiment_analytics[:exposures].to_i > total_required
			
			(experiment_analytics[:exposures].to_f / total_required) * 100
		end

		def performance_perc(kpi)
			return if control_conversion(kpi) == 0
			((experiment_conversion(kpi) / control_conversion(kpi)) - 1) * 100
		end

		def remaining_participants_needed(kpi)
			total_required = required_participants_needed_for(kpi).to_i
			return 0 if total_required < 0
			
			result = total_required - experiment_analytics[:exposures].to_i
			(result < 0) ? 0 : result.to_i
		end

		def restart!
			nuke_experiment!
			new_start_time = Time.now.utc
			@start_time = new_start_time
			save

			if active?
				SlotMachine.update_start_time_for_experiment(@id, new_start_time.to_i)
			end
		end

		def nuke_experiment!
			self.class.nuke_experiment(@id)
		end

		# clears all experiments and resets the slots.
		# warning - all experiments, including running ones, 
		# and completed ones will be permanently lost!
		#
		def self.nuke_all_experiments
			find_all_in_list(:pending).each do |experiment|
				experiment.nuke_experiment!
			end

			find_all_in_list(:active).each do |experiment|
				experiment.nuke_experiment!
			end

			find_all_in_list(:completed).each do |experiment|
				experiment.nuke_experiment!
			end

			Lacmus.fast_storage.del list_key_by_type(:pending)
			Lacmus.fast_storage.del list_key_by_type(:active)
			Lacmus.fast_storage.del list_key_by_type(:completed)

			SlotMachine.reset_slots_to_defaults
		end

		def self.restart_all_active_experiments
			find_all_in_list(:active).each do |experiment|
				experiment.restart!
			end
		end

		private

		# Generate a new (and unique) experiment id
		#
		# @example SlotMachine.generate_experiment_id # => 3
		#
		# @return [ Integer ] representing the new experiment id
		#
		def self.generate_experiment_id
			Lacmus.fast_storage.incr experiment_ids_key
		end

		def self.experiment_ids_key
			"#{LACMUS_PREFIX}-last-experiment-id"
		end

		# Returns the redis key for a given list type.
		#
		# @param [ Symbol, String ] list The list type, available options: active, pending, completed
		#
		def self.list_key_by_type(list)
			"#{LACMUS_PREFIX}-#{list.to_s}-experiments"
		end
	
		def self.all_from(list)
			experiments = []
			experiments_as_hash = SlotMachine.get_experiments(list)
			experiments_as_hash.each do |exp_hash|
				experiments << Experiment.new(exp_hash)
			end
			experiments
		end

		def self.kpi_key(experiment_id, is_control = false)
			"#{LACMUS_PREFIX}-#{is_control}-kpis-#{experiment_id.to_s}"
		end

		def self.exposure_key(experiment_id, is_control = false)
			"#{LACMUS_PREFIX}-#{is_control}-counter-#{experiment_id.to_s}"
		end

	end # of Experiment

	class ExperimentHistoryItem

		def initialize(user_id, experiment_id, exposed_at_as_int, is_control)
			@user_id 			 = user_id.to_i
			@exposed_at 	 = Time.at(exposed_at_as_int)
			@experiment_id = experiment_id.to_i
			@control 			 = is_control
			@experiment 	 = Experiment.find(@experiment_id)
		end

	end # of ExperimentHistoryItem
end # of Lacmus
