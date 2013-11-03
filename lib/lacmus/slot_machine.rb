# encoding: utf-8
module Lacmus
  # Responsible to display and manage the active experiments.
  # The active experiments are accessable using the experiment_slots method.
  #
  # @note Check out experiment_slots method for more info.
  module SlotMachine
    extend self

    # Represents the hash of control group slot, experiment id = 0.
    CONTROL_SLOT_HASH = {experiment_id: 0, start_time_as_int: 0}

    # Represents the hash of empty slot, meaning there is no
    # active experiment running. Used when adding new slots by the
    # resize method or when concluding an active experiment.
    EMPTY_SLOT_HASH = {experiment_id: -1, start_time_as_int: 0}

    # Represents the default experiment slots array with two slots,
    # one for control and one empty.
    DEFAULT_SLOT_HASH = [CONTROL_SLOT_HASH, EMPTY_SLOT_HASH]

    # Represents the last time (as integer) the attributes were cached.
    # Combined with $__lcms__worker_cache_interval, we can determine when
    # the cache is not valid anymore.
    $__lcms__loaded_at_as_int = 0

    # Reprsents the current active experiments (experiment_slots method).
    $__lcms__active_experiments = nil

    # The bread and butter of SlotMachine. Experiment slots is an array
    # representing the available slots. The first slot is always the control
    # group (identified by experiment_id = 0) followed by experiments.
    # A slot can also be inactive, inactive slot identified by experiment_id = -1.
    # The default experiment slots array consists of 2 slots, one for contorl
    # group and one for inactive experiment.
    #
    # @example Default experiment slots
    #   SlotMachine.experiment_slots
    #     # => [{experiment_id: 0, start_time_as_int: 0},
    #           {experiment_id: -1, start_time_as_int: 0}]
    #
    # @example 3 available slots,including 1 inactive slot.
    #   SlotMachine.experiment_slots
    #     # => [{experiment_id: 0, start_time_as_int: 0},
    #           {experiment_id: -1, start_time_as_int: 0},
    #           {experiment_id: 3, start_time_as_int: 1376475145}]
    #
    #
    # @return [ Array<Hash> ] Array of hashes contaning the active experiments.
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

    # Resize the experiment slots array based on the given new size.
    # It's only possible to decrease inactive slots, so if a slot is occupied
    # resize will fail, see examples. If resize is sucessful, all active
    # experiments will be restarted.
    #
    # @param [ Integer ] new_size The amount of slots you would to increase/decrease to.
    #
    # @example Increase amount of slots by 2
    #   experiment_slots:
    #     [{experiment_id: 0, start_time_as_int: 0}, {experiment_id: 3, start_time_as_int: 1376814732}]
    #
    #   SlotMachine.resize_and_reset_slot_array(4) # => true
    #   experiment_slots after resize:
    #     [{experiment_id: 0, start_time_as_int: 0}, {experiment_id: 3, start_time_as_int: 1376913212},
    #      {experiment_id: -1, start_time_as_int: 0}, {experiment_id: -1, start_time_as_int: 0}]
    #
    # @example Try to decrease active slots
    #   experiment_slots:
    #     [{experiment_id: 0, start_time_as_int: 0}, {experiment_id: 3, start_time_as_int: 1376913212},
    #      {experiment_id: 4, start_time_as_int: 1376913212}, {experiment_id: 8, start_time_as_int: 1376913212}]
    #
    #   SlotMachine.resize_and_reset_slot_array(2) # => false
    #   experiment_slots after resize:
    #     [{experiment_id: 0, start_time_as_int: 0}, {experiment_id: 3, start_time_as_int: 1376913212},
    #      {experiment_id: 4, start_time_as_int: 1376913212}, {experiment_id: 8, start_time_as_int: 1376913212}]
    #
    # @return [ Boolean ] True if resize was successful, false otherwise.
    #
    def resize_and_reset_slot_array(new_size)
      slot_array = experiment_slots
      new_size = new_size.to_i

      if new_size <= slot_array.count
        last_used_index = find_last_used_slot(slot_array)
        # Return false if there is an occupied slot
        # located after the size requested.
        return false if last_used_index > new_size
        slot_array = slot_array[0...new_size]
      else
        slots_to_add = new_size - slot_array.count
        slot_array += Array.new(slots_to_add){EMPTY_SLOT_HASH}
      end

      Experiment.restart_all_active_experiments
      update_start_time_for_all_experiments
      update_experiment_slots(slot_array)
      return true
    end

    # Update the start time data for a given experiment_id in experiments
    # slots.
    #
    # @param [ Integer ] experiment_id The experiment id
    # @param [ Integer ] start_time_as_int The new start time, ex: Time.now.utc.to_i
    #
    # @return True if successfully updated the start time, false otherwise. 
    # 
    def update_start_time_for_experiment(experiment_id, start_time_as_int)
      slot = experiment_slot_ids.index experiment_id
      return false if slot.nil?

      slots_hash = experiment_slots
      slots_hash[slot][:start_time_as_int] = start_time_as_int
      update_experiment_slots(slots_hash)
      return true
    end

    # Update start time for all active experiments in experiment_slots.
    # The new start_time value is being pulled from the Experiment object.
    #
    def update_start_time_for_all_experiments
      slots = experiment_slots
      slots.each do |slot|
        experiment_id = slot[:experiment_id].to_i
        next if Experiment.special_experiment_id?(experiment_id)

        experiment = Experiment.find_in_list(experiment_id, :active)
        slot[:start_time_as_int] = experiment.start_time.to_i
      end
      update_experiment_slots(slots)
    end

    # Find the index of the last occupied slot in the given slot_array.
    #
    # @param [ Array<Hash> ] slot_array Array of experiment slots
    #
    # @example
    #   experiment_slots: [{:experiment_id=>0, :start_time_as_int=>0}, {:experiment_id=>-1, :start_time_as_int=>1233242234},
    #                      {:experiment_id=>3, :start_time_as_int=>13212380}, {:experiment_id=>-1, :start_time_as_int=>0}]
    #
    #   find_last_used_slot(slot_array) # => 2
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
      experiment_slot_ids_without_control_group.any? {|i| i != -1}
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
    #   experiment_slot_ids = [5, 13, -1, 9]
    #   SlotMachine.get_experiment_id_from_slot(1) # => 13
    #
    # @return [ Integer ] The experiment id in the given slot
    #
    def get_experiment_id_from_slot(slot)
      experiment_slot_ids[slot.to_i]
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
    #   is no longer active.
    #
    # @return [ Integer ] The last experiment reset time.
    #
    def start_time(experiment_id)
      experiment_hash = experiment_slots.select{|i| i[:experiment_id].to_s == experiment_id.to_s}[0]
      experiment_hash[:start_time_as_int] if experiment_hash
    end

    # Reset the worker's cache so next time experiment slots
    # is called we'll get the data from redis.
    #
    def reset_worker_cache
      $__lcms__loaded_at_as_int = 0
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

  end # of SlotMachine
end # of Lacmus