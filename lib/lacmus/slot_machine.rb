require 'lacmus/settings'
require 'redis'

module Lacmus
	module SlotMachine
		extend self

		# Constants
		CONTROL_SLOT_HASH = {:experiment_id => 0, :start_time_as_int => 0}
		EMPTY_SLOT_HASH   = {:experiment_id => -1, :start_time_as_int => 0}
		DEFAULT_SLOT_HASH = [CONTROL_SLOT_HASH, EMPTY_SLOT_HASH]

		# Represents (in seconds) how long the cache is going to be valid.
		# Default to 60 means we'll query the database only once a minute.
		$__lcms__worker_cache_interval = 60

		# Represents the last time (as integer) the attributes were cached.
		# Combined with $__lcms__worker_cache_interval, we can determine when
		# the cache is not valid anymore.
		$__lcms__loaded_at_as_int = 0

		# Reprsents the current active experiments (experiment_slots method).
		$__lcms__active_experiments = nil

		# Create a new experiment and add it to the pending list.
		#
		# == Returns
		# Integer representing the new experiment id.
		#
		def create_experiment(name, description, opts = {})
			experiment_id 		 	= generate_experiment_id
			experiment_metadada = {
				:experiment_id => experiment_id,
				:name 				 => name,
				:description 	 => description,
				:status 			 => :pending
			}.merge!(opts)

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
		def activate_experiment(experiment_id)
			move_experiment(experiment_id, :pending, :active)
		end

		# Reactivates a completed exeprtiment
		def reactivate_experiment(experiment_id)
			move_experiment(experiment_id, :completed, :active)
		end

		# move experiment from one list to another
		#
		# valid list types - :pending, :active, :completed
		# returns false if experiment not found
		def move_experiment(experiment_id, from_list, to_list)
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
		def get_experiment_from(list, experiment_id)
			return {} if experiment_id.nil?
			experiment = Lacmus.fast_storage.zrangebyscore list_key_by_type(list), experiment_id, experiment_id
			return {} if experiment.nil? || experiment.empty?
			Marshal.load(experiment.first)
		end

		def get_experiments(list)
			experiments_ary = []
			experiments = Lacmus.fast_storage.zrange list_key_by_type(list), 0, -1
			experiments.each do |experiment|
				experiments_ary << Marshal.load(experiment)
			end
			experiments_ary
		end

		# returns an experiment from either of the lists
		def find_experiment(experiment_id)
			experiment = {}
			[:active, :pending, :completed].each do |list|
				exp = get_experiment_from(list, experiment_id)
				experiment = exp unless exp.empty?
			end
			experiment
		end

		def get_control_group
			get_experiment_from(:active, 0)
		end

		# restart an active experiment
		# return if the experiment isn't active.
		def restart_experiment(experiment_id)
			slot = experiment_slot_ids.index experiment_id
			return if slot.nil?

			slots_hash = experiment_slots
			ex = Experiment.new(experiment_id)
			ex.nuke
			slots_hash[slot][:start_time_as_int] = Time.now.utc.to_i
			ex.start_time = Time.now
			ex.save
			update_experiment_slots(slots_hash)
			reset_worker_cache
		end

		# adds an experiment with metadata to a given list
		# 
		# list
		# accepts the following values: pending, active, completed
		def add_experiment_to(list, experiment_metadada)
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
		def deactivate_experiment(experiment_id)
			remove_experiment_from_slot(experiment_id)
			move_experiment(experiment_id, :active, :completed)
		end

		# removes an experiment from a list
		# 
		# list
		# accepts the following values: pending, active, completed
		def remove_experiment_from(list, experiment_id)
			Lacmus.fast_storage.zremrangebyscore list_key_by_type(list), experiment_id, experiment_id

			if list.to_s == 'active'
				remove_experiment_from_slot(experiment_id)
			end
		end	

		def deactivate_all_experiments
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
		def nuke_all_experiments
			get_experiments(:pending).each do |experiment|
				Experiment.nuke_experiment(experiment[:experiment_id])
			end

			get_experiments(:active).each do |experiment|
				Experiment.nuke_experiment(experiment[:experiment_id])
			end

			get_experiments(:completed).each do |experiment|
				Experiment.nuke_experiment(experiment[:experiment_id])
			end

			Lacmus.fast_storage.del list_key_by_type(:pending)
			Lacmus.fast_storage.del list_key_by_type(:active)
			Lacmus.fast_storage.del list_key_by_type(:completed)

			reset_slots_to_defaults
		end

		# Resize the experiment slots array based on the
		# given new size.
		def resize_and_reset_slot_array(new_size)
			slot_array = experiment_slots
			last_reset_hash = {}
			new_size = new_size.to_i

			if new_size <= slot_array.count
				last_used_index = find_last_used_slot(slot_array)
				# return false if there is an occupied slot
				# located after the size requested.
				return false if last_used_index > new_size
				slot_array = slot_array[0...new_size]
			else
				slots_to_add = new_size - slot_array.count
				slot_array += Array.new(slots_to_add){EMPTY_SLOT_HASH}
			end

			get_experiments(:active).each do |experiment_hash|
				exp = Experiment.new(experiment_hash[:experiment_id])
				exp.restart!
				exp.reload
				last_reset_hash.merge!({exp.id => exp.start_time.to_i})
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

			update_experiment_slots(slot_array)
			reset_worker_cache
			return true
		end

		# Find the index of the last occupied slot in the given slot_array.
		#
		# @param [ Array<Hash> ] slot_array Array of experiment slots
		#
		# @example
		# 	slot_array = [{:experiment_id=>0, :start_time_as_int=>0}, {:experiment_id=>-1, :start_time_as_int=>1233242234},
		#									{:experiment_id=>3, :start_time_as_int=>13212380}, {:experiment_id=>-1, :start_time_as_int=>0}]
		#
		# 	find_last_used_slot(slot_array) # => 2
		#
		# @return [ nil ] if slot_array contains empty slots only (experiment_id = -1).
		# @return [ Integer ] if there is any active experiment, representing the last available index.
		#
		def find_last_used_slot(slot_array)
			slot_array.reverse.each_with_index do |i, index|
				return (slot_array.count - index) if i[:experiment_id] != -1
			end
		end

		# Check whether there are any active experiments.
		#
		# @return [ Boolean ]
		#
		def any_active_experiments?
			(get_experiments(:active).count > 0)
		end

		# Reset the worker's cache so next time experiment slots
		# is called we'll get the data from redis.
		#
		def reset_worker_cache
			$__lcms__loaded_at_as_int = 0
		end

		# Permanently deletes an axperiment
		#
		# @param [ Symbol, String ] list The list this experiment belongs to,
		# 	available options: active, pending, completed
		# @param [ Integer ] experiment_id Id of the experiment.
		#
		def destroy_experiment(list, experiment_id)
			remove_experiment_from(list, experiment_id)
			Experiment.nuke_experiment(experiment_id)
		end

		# Returns the redis key for a given list type
		#
		# @param [ Symbol, String ] list The list type, available options: active, pending, completed
		#
		def list_key_by_type(list)
			"#{LACMUS_PREFIX}-#{list.to_s}-experiments"
		end

		# Find within the experiment_slot_ids in redis the first
		# empty slot (represented with -1 value).
		#
		# @return [ Integer, nil] The index of the available slot.
		#
		def find_available_slot
			slots = experiment_slot_ids
			slots.index -1
		end

		# Fills a slot with the given experiment_id. No action will be
		# taken if the slot is already taken.
		#
		# @param [ Integer ] experiment_id
		# @param [ Integer ] slot 
		#
		def place_experiment_in_slot(experiment_id, slot)
			slots = experiment_slots
			return unless slots[slot] == EMPTY_SLOT_HASH

			slots[slot] = {:experiment_id => experiment_id, :start_time_as_int => Time.now.utc.to_i}
			update_experiment_slots(slots)
		end

		# Remove the given experiment id from experiment_slots array.
		# No action will be taken if experiment_id is not part of
		# experiment_slots array.
		#
		# @param [ Integer ] experiment_id
		#
		def remove_experiment_from_slot(experiment_id)
			slots = experiment_slots
			return if slots.empty?

			index_to_replace = slots.find_index {|i| i[:experiment_id].to_i == experiment_id.to_i}
			if index_to_replace
				slots[index_to_replace] = EMPTY_SLOT_HASH
				update_experiment_slots(slots)
			end
		end

		# Returns the experiment id occupying the
		# given slot (index starting from 0).
		#
		# @param [ Integer ] slot
		#
		# @example
		# 	experiment_slot_ids = [5, 13, -1, 9]
		# 	SlotMachine.get_experiment_id_from_slot(1) # => 13
		#
		# @return [ Integer ] The experiment id in the given slot
		#
		def get_experiment_id_from_slot(slot)
			experiment_slot_ids[slot.to_i]
		end

		# Returns the current active experiments. For performence reasons
		# we'll try to fetch the data from memory first, if we can't (because data
		# is outdated, for example) we'll get it from redis.
		#
		# If we don't have such redis key, the default expeiment slots
		# will initialize.
		#
		# @return [ Array<Hash> ] Array of hashes contaning the active experiments
		#
		def experiment_slots
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

		# Convenience method to return the ids of the active experiments.
		#
		# @return [ Array<Inreger> ] Array of experiment ids.
		#
		def experiment_slot_ids
			experiment_slots.collect{|slot| slot[:experiment_id].to_i}
		end

		# Convenience method to return the ids of the active experiments
		# excluding the control group slot.
		#
		# @return [ Array<Inreger> ] Array of experiment ids.
		#
		def experiment_slot_ids_without_control_group
			experiment_slot_ids[1..-1]
		end

		# Marshal the given experiment slot ids and update the redis key.
		#
		# @param [ Array<Hash> ] slots Array of experiment slot ids
		#
		def update_experiment_slots(slots)
			Lacmus.fast_storage.set slot_usage_key, Marshal.dump(slots)
		end

		# Reset the active experiment slots array.
		#
		def reset_slots_to_defaults
			Lacmus.fast_storage.del slot_usage_key
		end

		# Clears the entire experiment slots array,
		# without modifying the size of the array.
		#
		def clear_experiment_slot_ids
			result = experiment_slots
			slots_to_add = result.size - 1
			clean_array = [CONTROL_SLOT_HASH] + Array.new(slots_to_add){EMPTY_SLOT_HASH}
			update_experiment_slots(clean_array)
		end

		# Returns the last experiment reset of the given active
		# experiment_id.
		#
		# @param [ Integer, String ] experiment_id The experiment id
		#
		# @return [ nil ] if there is no such experiment_id or the experiment
		# 	is no longer active.
		#
		# @return [ Integer ] The last experiment reset time.
		#
		def last_experiment_reset(experiment_id)
			cached_exp = experiment_slots.select{|i| i[:experiment_id].to_s == experiment_id.to_s}[0]
			return if cached_exp.nil?
			return cached_exp[:start_time_as_int]
		end

		private

		# Intialize the experiment slots array using the
		# DEFAULT_SLOT_HASH constant.
		#
		def init_slots
			$__lcms__active_experiments = DEFAULT_SLOT_HASH.dup
			$__lcms__loaded_at_as_int = Time.now.utc.to_i
			update_experiment_slots($__lcms__active_experiments)
		end

		# Check if the cached global variables are still relevant.
		#
		# @return [ Boolean ] true if the cache is valid, false otherwise.
		#
		def worker_cache_valid?
			$__lcms__loaded_at_as_int.to_i > (Time.now.utc.to_i - $__lcms__worker_cache_interval)
		end

		# Convenience method to work with experiment slots.
		#
		# @return [ String ] String representing the redis key
		#
		def slot_usage_key
			"#{LACMUS_PREFIX}-slot-usage"
		end

		# Generate a new (and unique) experiment id
		#
		# @example SlotMachine.generate_experiment_id # => 3
		#
		# @return [ Integer ] representing the new experiment id
		#
		def generate_experiment_id
			Lacmus.fast_storage.incr "#{LACMUS_PREFIX}-last-experiment-id"
		end

	end # of SlotMachine
end # of Lacmus