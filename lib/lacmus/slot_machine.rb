require_relative 'settings'
require_relative 'fast_storage'
require 'redis'
require 'pry'
require 'json'

module Lacmus
	module SlotMachine

		# Constants
		DEFAULT_SLOTS_SIZE = 1

		# Create a new experiment and add it to the pending list.
		#
		# == Returns
		# Integer representing the new experiment id.
		#
		def self.create_experiment(name, description)
			experiment_id 		 	= generate_experiment_id
			experiment_metadada = {:experiment_id => experiment_id, :name => name, :description => description}

			add_experiment_to(:pending, experiment_metadada)
			experiment_id
		end

		# Activate an exeprtiment
		# 
		# this is done by trying to find an empty experiment slot
		# and moving the experiment from the pending list to the active
		# ones list. 
		# 
		# returns true on success, false on failure
		def self.activate_experiment(experiment_id)
			move_experiment(experiment_id, :pending, :active)
		end

		# move experiment from one list to another
		#
		# valid list types - :pending, :active, :completed
		# returns false if experiment not found
		def self.move_experiment(experiment_id, from_list, to_list)
			experiment = get_experiment_from(from_list, experiment_id)
			return false if experiment.empty?

			if from_list == :pending && to_list == :active
				experiment.merge!({:start_time_as_int => Time.now.utc.to_i})
			end
			result = add_experiment_to(to_list, experiment)
			return false unless result

			remove_experiment_from(from_list, experiment_id)
			true
		end

		# returns an experimend from one of the lists
		#
		# list
		# accepts the following values: pending, active, completed
		def self.get_experiment_from(list, experiment_id)
			return {} if experiment_id.nil?
			experiment = Lacmus.fast_storage.zrangebyscore list_key_by_type(list), experiment_id, experiment_id
			return {} if experiment.nil? || experiment.empty?
			Marshal.load(experiment.first)
		end

		# adds an experiment with metadata to a given list
		# 
		# list
		# accepts the following values: pending, active, completed
		def self.add_experiment_to(list, experiment_metadada)
			if list == :active
				available_slot_id = find_available_slot
				return false if available_slot_id.nil?
				place_experiment_in_slot(experiment_metadada[:experiment_id], available_slot_id)
			end
			Lacmus.fast_storage.zadd list_key_by_type(list), experiment_metadada[:experiment_id], Marshal.dump(experiment_metadada)
			true
		end

		# removes an experiment from the active experiments list
		# and clears it's slot
		def self.deactivate_experiment(experiment_id)
			move_experiment(experiment_id, :active, :completed)
			remove_experiment_from_slot(experiment_id)
		end

		# removes an experiment from a list
		# 
		# list
		# accepts the following values: pending, active, completed
		def self.remove_experiment_from(list, experiment_id)
			Lacmus.fast_storage.zremrangebyscore list_key_by_type(list), experiment_id, experiment_id
			if list == :active
				remove_experiment_from_slot(experiment_id)
			end
		end	

		def self.deactivate_all_experiments
			Lacmus.fast_storage.multi do
				deactivated_experiments = get_experiments(:active)
				
				deactivated_experiments.each do |experiment|
					deactivate_experiment(experiment[:id])
				end
			end
		end

		# clears all experiments and resets the slots.
		# warning - all experiments, including running ones, 
		# and completed ones will be permanently lost!
		def self.nuke_all_experiments
			Lacmus.fast_storage.del list_key_by_type(:pending)
			Lacmus.fast_storage.del list_key_by_type(:active)
			Lacmus.fast_storage.del list_key_by_type(:completed)
			reset_slots_to_defaults
		end

		def self.resize_slot_array(new_size)
			slot_array = experiment_slots
			return false if new_size <= slot_array.count

			slots_to_add = new_size - slot_array.count
			slot_array += Array.new(slots_to_add){0}
			Lacmus.fast_storage.set slot_usage_key, Marshal.dump(slot_array)
			true
		end

		def self.get_experiments(list)
			Lacmus.fast_storage.zrange list_key_by_type(list), 0, -1
		end

		private

		# here we look for an array stored in redis
		# and we look for the first 0 in the array that we find
		# the 0 represents an open slot
		# returns nil if no slots are available
		def self.find_available_slot
			slots = experiment_slots
			slots.index 0
		end

		# takes a free slot given to it, and assignes an experiment
		# to it. is the slot is already taken, nothing will happen,
		# and the function will return false.
		def self.place_experiment_in_slot(experiment_id, slot)
			slots = experiment_slots
			return unless slots[slot].zero?

			slots[slot] = experiment_id
			set_updated_slots(slots)
		end

		# clears a slot for a new experiment, by turning
		# the	previous experiment's id into 0
		def self.remove_experiment_from_slot(experiment_id)
			slots = experiment_slots
			return if slots.empty?

			index_to_replace = slots.index experiment_id
			slots[index_to_replace] = 0
			set_updated_slots(slots)
		end

		def self.set_updated_slots(slots)
			Lacmus.fast_storage.set slot_usage_key, Marshal.dump(slots)
		end

		# returns the appropriate key for the given list status
		#
		# list
		# accepts the following values: pending, active, completed
		def self.list_key_by_type(list)
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-#{list.to_s}-experiments"
		end

		# clear all experiment slots, leaving the number of slots untouched
		def self.clear_experiment_slots
			result = Marshal.load(Lacmus.fast_storage.get slot_usage_key)
			clean_array = Array.new(result.count){0}
			Lacmus.fast_storage.set slot_usage_key, Marshal.dump(clean_array)
		end

		# reset slot machine to default
		def self.reset_slots_to_defaults
			Lacmus.fast_storage.del slot_usage_key
		end

		def self.init_slots
			slot_array = Array.new(DEFAULT_SLOTS_SIZE){0}
			Lacmus.fast_storage.set slot_usage_key, Marshal.dump(slot_array)
			slot_array
		end

		def self.experiment_slots
			result = Lacmus.fast_storage.get slot_usage_key
			result ? Marshal.load(result) : init_slots
		end

		def self.slot_usage_key
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-slot-usage"
		end

		def self.generate_experiment_id
			Lacmus.fast_storage.incr "#{Lacmus::Settings::LACMUS_NAMESPACE}-last-experiment-id"
		end

	end
end