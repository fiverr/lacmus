require_relative 'settings'
require_relative 'fast_storage'
require 'redis'
require 'pry'
require 'json'

module Lacmus
	module SlotMachine

		DEFAULT_SLOTS_SIZE = 1
		# creates a new experiment
		#
		# New experiments are automatically added 
		# to the pending list, and wait there to be actiacted
		def self.create_experiment(name, description)
			experiment_id = generate_experiment_id
			add_experiment_to(:pending, {:name => name, :description => description, :experiment_id => experiment_id})
			experiment_id
		end

		# activates an exeprtiment
		# 
		# this is done by trying to find an empty experiment slot
		# and moving the experiment from the pending list to the active
		# ones list. 
		# 
		# returns true on success, false on failure
		def self.activate_experiment(experiment_id)
			return activate_experiment_from(:pending, experiment_id)
		end

		# move experiment from one list to another
		#
		# valid list types - :pending, :active, :completed
		# returns false if experiment not found
		def self.move_experiment(experiment_id, from_list, to_list)
			# Lacmus.fast_storage.multi do
				experiment = get_experiment_from(from_list, experiment_id)
				return false if experiment.empty?

				add_experiment_to(to_list, experiment)
				remove_experiment_from(from_list, experiment_id)
			# end
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
			clear_experiment_slots
		end

		# tries to find an empty slot for a completed experiment
		# if it finds one, it moves the experiment into the
		# active experiments list and updates the slots
		#
		# returns true on success, false on failure
		def self.activate_experiment_from(list, experiment_id)
			slot = find_available_slot
			return false if slot.nil?
			experiment = get_experiment_from(list_key_by_type(list), experiment_id)
			return false if experiment.nil?
			experiment.merge!({:start_time_as_int => Time.now.utc.to_i}) if list == :pending
			add_experiment_to(:active, experiment)
			place_experiment_in_slot(experiment_id, slot)
			true
		end

		def self.set_available_slots(slots_to_use)
			slot_array = experiment_slots
			
			#create it for the first time
			if slot_array.empty?
				slot_array = Array.new(slots_to_use){0}
				Lacmus.fast_storage.set slot_usage_key, Marshal.dump(slot_array)
				return true
			end

			return false if slots_to_use < slot_array.count
			return false if slots_to_use == slot_array.count
				
			# enlarge the slot list
			if slots_to_use > slot_array.count
				slots_to_add = slots_to_use - slot_array.count
				slot_array << Array.new(slots_to_add){0}
				Lacmus.fast_storage.set slot_usage_key, Marshal.dump(slot_array)
				return true
			end
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
			if slots.empty?
				# fist run, nothing is taken yet
				set_available_slots(DEFAULT_SLOTS_SIZE)
				return 0
			end
			slots.index 0
		end

		# takes a free slot given to it, and assignes an experiment
		# to it. is the slot is already taken, nothing will happen,
		# and the function will return false.
		def self.place_experiment_in_slot(experiment_id, slot)
			slots = experiment_slots
			slots[slot] = experiment_id
			Lacmus.fast_storage.set slot_usage_key, Marshal.dump(slots)
		end

		# clears a slot for a new experiment, buy turning
		# the	previous experiment's id into 0
		def self.remove_experiment_from_slot(experiment_id)
			return if experiment_slots.empty?
			index_to_replace = experiment_slots.index experiment_id
			place_experiment_in_slot(0,index_to_replace)
		end

		# returns the appropriate key for the given list status
		#
		# list
		# accepts the following values: pending, active, completed
		def self.list_key_by_type(list)
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-#{list.to_s}-experiments"
		end

		# clear all experiment slots
		def self.clear_experiment_slots
			Lacmus.fast_storage.set slot_usage_key, Marshal.dump([])
		end

		def self.experiment_slots
			result = Lacmus.fast_storage.get slot_usage_key
			if result
				Marshal.load(result)
			else
				[]
			end
		end

		def self.slot_usage_key
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-slot-usage"
		end

		def self.generate_experiment_id
			Lacmus.fast_storage.incr "#{Lacmus::Settings::LACMUS_NAMESPACE}-last-experiment-id"
		end

	end
end