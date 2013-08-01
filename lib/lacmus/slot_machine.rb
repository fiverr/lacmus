require_relative 'settings'
require_relative 'fast_storage'
require 'redis'
require 'pry'

module Lacmus
	module SlotMachine

		# Constants
		CONTROL_SLOT_HASH = {:experiment_id => 0, :start_time_as_int => 0}
		EMPTY_SLOT_HASH   = {:experiment_id => -1, :start_time_as_int => 0}
		DEFAULT_SLOT_HASH = [CONTROL_SLOT_HASH, EMPTY_SLOT_HASH]

		# Glboal Worker-Level Variables (Worker Cache)
		$__lcms__worker_cache_active		= true
		$__lcms__worker_cache_interval 	= 60
		$__lcms__loaded_at_as_int   		= 0
		$__lcms__active_experiments 		= nil

		# Create a new experiment and add it to the pending list.
		#
		# == Returns
		# Integer representing the new experiment id.
		#
		def self.create_experiment(name, description, opts = {})
			experiment_id 		 	= generate_experiment_id
			experiment_metadada = {:experiment_id => experiment_id, :name => name, :description => description, :status => :pending}
			experiment_metadada.merge!(opts)

			add_experiment_to(:pending, experiment_metadada)
			experiment_id
		end

		# Activate an exeprtiment
		# 
		# this is done by trying to find an empty experiment slot
		# and moving the experiment from the pending list to the active
		# ones list. q
		# 
		# returns true on success, false on failure
		def self.activate_experiment(experiment_id)
			move_experiment(experiment_id, :pending, :active)
		end

		# Reactivates a completed exeprtiment
		def self.reactivate_experiment(experiment_id)
			move_experiment(experiment_id, :completed, :active)
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

			if from_list == :completed && to_list == :active
				experiment.merge!({:end_time_as_int => nil})
			end

			if from_list == :active && to_list == :completed
				experiment.merge!({:end_time_as_int => Time.now.utc.to_i})
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

		def self.get_experiments(list)
			experiments_ary = []
			experiments = Lacmus.fast_storage.zrange list_key_by_type(list), 0, -1
			experiments.each do |experiment|
				experiments_ary << Marshal.load(experiment)
			end
			experiments_ary
		end

		# returns an experiment from either of the lists
		def self.find_experiment(experiment_id)
			experiment = {}
			[:active, :pending, :completed].each do |list|
				exp = get_experiment_from(list, experiment_id)
				experiment = exp unless exp.empty?
			end
			experiment
		end

		def self.get_control_group
			get_experiment_from(:active, 0)
		end

		# restart an active experiment
		# return if the experiment isn't active.
		def self.restart_experiment(experiment_id)
			slot = experiment_slot_ids.index experiment_id
			return if slot.nil?

			slots_hash = experiment_slots
			ex = Experiment.new(experiment_id)
			ex.nuke
			slots_hash[slot][:start_time_as_int] = Time.now.utc.to_i
			ex.start_time = Time.now
			ex.save
			set_updated_slots(slots_hash)
			reset_worker_cache
		end

		# adds an experiment with metadata to a given list
		# 
		# list
		# accepts the following values: pending, active, completed
		def self.add_experiment_to(list, experiment_metadada)
			experiment_metadada.merge!({:status => list.to_sym})
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
			remove_experiment_from_slot(experiment_id)
			move_experiment(experiment_id, :active, :completed)
		end

		# removes an experiment from a list
		# 
		# list
		# accepts the following values: pending, active, completed
		def self.remove_experiment_from(list, experiment_id)
			Lacmus.fast_storage.zremrangebyscore list_key_by_type(list), experiment_id, experiment_id

			if list.to_s == 'active'
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
			get_experiments(:pending).each do |experiment|
				Lacmus::Experiment.nuke_experiment(experiment[:experiment_id])
			end

			get_experiments(:active).each do |experiment|
				Lacmus::Experiment.nuke_experiment(experiment[:experiment_id])
			end

			get_experiments(:completed).each do |experiment|
				Lacmus::Experiment.nuke_experiment(experiment[:experiment_id])
			end

			Lacmus.fast_storage.del list_key_by_type(:pending)
			Lacmus.fast_storage.del list_key_by_type(:active)
			Lacmus.fast_storage.del list_key_by_type(:completed)

			reset_slots_to_defaults
		end

		def self.resize_and_reset_slot_array(new_size)
			slot_array = experiment_slots
			last_reset_hash = {}
			new_size = new_size.to_i

			if new_size <= slot_array.count
				last_used_index = find_last_used_slot(slot_array)
				# if there is an experiment occupying a slot that is
				# located after the size requested, we do not allow
				return false if last_used_index > new_size
				slot_array = slot_array[0...new_size]
			else
				slots_to_add = new_size - slot_array.count
				slot_array += Array.new(slots_to_add){EMPTY_SLOT_HASH}
			end

			get_experiments(:active).each do |experiment_hash|
				exp_id = experiment_hash[:experiment_id]
				Lacmus::Experiment.new(exp_id).restart!
				last_reset_as_int = Lacmus::Experiment.new(exp_id).start_time.to_i
				last_reset_hash.merge!({exp_id.to_i => last_reset_as_int})
			end

			slot_array.each do |slot|
				exp_id_for_slot = slot[:experiment_id].to_i
				next if exp_id_for_slot == -1
				if exp_id_for_slot == 0
					slot[:start_time_as_int] = Time.now.utc.to_i
				else
					slot[:start_time_as_int] = last_reset_hash[exp_id_for_slot]
				end
			end

			Lacmus.fast_storage.set slot_usage_key, Marshal.dump(slot_array)
			reset_worker_cache
			return true
		end

		# [1,2,3,4,5,-1,-1,-1]
		# [1,23,4,4,4,-1, 23, 43]
		def self.find_last_used_slot(slot_array)
			slot_array.reverse.each_with_index do |i, index|
				return (slot_array.count - index) if i[:experiment_id] != -1
			end
		end

		def self.any_active_experiments?
			(get_experiments(:active).count > 0)
		end

		def self.worker_cache_active=(value)
			$__lcms__worker_cache_active = value
		end

		def self.worker_cache_interval=(value)
			$__lcms__worker_cache_interval = value.to_i
		end

		def self.reset_worker_cache
			$__lcms__loaded_at_as_int = 0
		end

		# permanently deletes an axperiment
		def self.destroy_experiment(list, experiment_id)
			remove_experiment_from(list, experiment_id)
			Lacmus::Experiment.nuke_experiment(experiment_id)
		end

		# returns the appropriate key for the given list status
		#
		# list
		# accepts the following values: pending, active, completed
		def self.list_key_by_type(list)
			"#{Lacmus.namespace}-#{list.to_s}-experiments"
		end


		private

		# here we look for an array stored in redis
		# and we look for the first -1 in the array that we find
		# the 0 represents an open slot
		# returns nil if no slots are available
		def self.find_available_slot
			slots = experiment_slot_ids
			slots.index -1
		end

		# takes a free slot given to it, and assignes an experiment
		# to it. is the slot is already taken, nothing will happen,
		# and the function will return false.
		def self.place_experiment_in_slot(experiment_id, slot)
			slots = experiment_slots
			return unless slots[slot] == EMPTY_SLOT_HASH

			slots[slot] = {:experiment_id => experiment_id, :start_time_as_int => Time.now.utc.to_i}
			set_updated_slots(slots)
		end

		# clears a slot for a new experiment, by turning
		# the	previous experiment's id into 0
		# if *index_to_replace* is nil, the experiment was already
		# removed from experiment_slot_ids.
		def self.remove_experiment_from_slot(experiment_id)
			slots = experiment_slots
			return if slots.empty?

			index_to_replace = slots.find_index {|i| i[:experiment_id].to_i == experiment_id.to_i}
			if index_to_replace
				slots[index_to_replace] = EMPTY_SLOT_HASH
				set_updated_slots(slots)
			end
		end

		def self.get_experiment_id_from_slot(slot)
			experiment_slot_ids[slot.to_i]
		end

		def self.set_updated_slots(slots)
			Lacmus.fast_storage.set slot_usage_key, Marshal.dump(slots)
		end

		# clear all experiment slots, leaving the number of slots untouched
		def self.clear_experiment_slot_ids
			result = Marshal.load(Lacmus.fast_storage.get slot_usage_key)
			slots_to_add = result.size - 1
			clean_array = [CONTROL_SLOT_HASH] + Array.new(slots_to_add){EMPTY_SLOT_HASH}
			Lacmus.fast_storage.set slot_usage_key, Marshal.dump(clean_array)
		end

		# reset slot machine to default
		def self.reset_slots_to_defaults
			Lacmus.fast_storage.del slot_usage_key
		end

		def self.init_slots
			$__lcms__active_experiments = DEFAULT_SLOT_HASH.dup
			$__lcms__loaded_at_as_int = Time.now.utc.to_i
			Lacmus.fast_storage.set slot_usage_key, Marshal.dump($__lcms__active_experiments)
		end

		def self.experiment_slots
			if worker_cache_valid?
				return $__lcms__active_experiments
			end

			slot_hash_from_redis = Lacmus.fast_storage.get slot_usage_key
			if slot_hash_from_redis
				$__lcms__active_experiments = Marshal.load(slot_hash_from_redis)
				$__lcms__loaded_at_as_int = Time.now.utc.to_i
			else
				init_slots
			end
			$__lcms__active_experiments
		end

		def self.worker_cache_valid?
			$__lcms__worker_cache_active &&
				$__lcms__loaded_at_as_int.to_i > (Time.now.utc.to_i - $__lcms__worker_cache_interval)
		end

		def self.last_experiment_reset(experiment_id)
			cached_exp = experiment_slots.select{|i| i[:experiment_id].to_s == experiment_id.to_s}[0]
			return if cached_exp.nil?
			return cached_exp[:start_time_as_int]
		end

		def self.experiment_slot_ids
			experiment_slots.collect{|slot| slot[:experiment_id].to_i}
		end

		def self.experiment_slot_ids_without_control_group
			experiment_slot_ids[1..-1]
		end

		def self.slot_usage_key
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-slot-usage"
		end

		def self.generate_experiment_id
			Lacmus.fast_storage.incr "#{Lacmus::Settings::LACMUS_NAMESPACE}-last-experiment-id"
		end

	end
end