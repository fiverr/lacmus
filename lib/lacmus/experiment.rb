# encoding: utf-8
module Lacmus
  class Experiment

    # Raised when trying to initialize an experiment object
    # with somethong other than a Hash.
    class InvalidInitValue < StandardError; end

    MAX_RECENT_COMPLETED_EXPS = (60 * 60 * 24 * 7) # 7 days

    # Accessors
    attr_accessor :id
    attr_accessor :name
    attr_accessor :description
    attr_accessor :start_time
    attr_accessor :end_time
    attr_accessor :status
    attr_accessor :screenshot_url
    attr_accessor :errors

    attr_reader :control_kpis
    attr_reader :experiment_kpis
    attr_reader :control_analytics
    attr_reader :experiment_analytics

    def initialize(options = {})
      raise InvalidInitValue unless options.is_a?(Hash)
      options = ActiveSupport::HashWithIndifferentAccess.new(options)

      @id                   = options[:id]
      @status               = options[:status]
      @name                 = options[:name]
      @description          = options[:description]
      @screenshot_url       = options[:screenshot_url]
      @start_time           = options[:start_time]
      @end_time             = options[:end_time]
      @control_kpis         = load_experiment_kpis(true)
      @experiment_kpis      = load_experiment_kpis
      @control_analytics    = load_experiment_analytics(true)
      @experiment_analytics = load_experiment_analytics
      @errors               = []
    end

    # Create a new experiment and save it.
    #
    # @param options [ Hash ] options The experiment metadata.
    # @option [ String ] name The experiment name.
    # @option [ String ] description The experiment description.
    # @option [ String ] screenshot_url A url showing the experiment in place,
    #   can be used as visiable representation.
    #
    # @example Create a new experiment
    #   Expierment.create!(name: 'Join now button', description: 'Testing join now button as green instead of blue',
    #                      screenshot_url: 'http://bit.ly/abLG57')
    #
    # @return [ Experiment ] The newly created experiment object
    #
    def self.create!(options = {})
      attrs = {
        id:     generate_experiment_id,
        status: :pending
      }.merge(options)

      exp_obj = new(attrs)
      exp_obj.save
      exp_obj.add_to_list(:pending)
      exp_obj
    end

    # Add an experiment to the given list. Experiments are belonged to
    # a list based on their status, so the active list stores all the
    # experiments with the active status etc.
    #
    # @param [ Symbol ] list The list to add the experiment to.
    #   Available options: :pending, :active, :completed
    #
    # @example Add a pending experiment to the active list
    #   experiment = Expierment.create!(name: 'Join now button')
    #   experiment.status # => 'pending'
    #   experiment.add_to_list(:active) # => true
    #
    #   experiment.status # => 'active'
    #
    # @return True if added successfully, false otherwise. 
    #
    def add_to_list(list)
      if list.to_sym == :active
        available_slot_id = SlotMachine.find_available_slot
        return false if available_slot_id.nil?
        SlotMachine.place_experiment_in_slot(@id, available_slot_id)
      end

      @status = list.to_sym
      save

      Lacmus.fast_storage.zadd self.class.list_key_by_type(list), @id, Marshal.dump(self.to_hash)
      return true
    end

    # Removes an experiment from the given list.
    #
    # @param [ Symbol ] list The list to remove the experiment from.
    #   Available options: :pending, :active, :completed
    #
    # @example Remove a pending experiment
    #   experiment = Expierment.create!(name: 'Join now button')
    #   experiment.id # => 1
    #   experiment.status # => 'pending'
    #   experiment.remove_from_list(:pending)
    #
    #   Experiment.find(1) # => nil
    #
    def remove_from_list(list)
      if list.to_sym == :active
        SlotMachine.remove_experiment_from_slot(@id)
      end
      Lacmus.fast_storage.zremrangebyscore self.class.list_key_by_type(list), @id, @id
    end 

    # Removing an experiment from the current list
    # and adding it to the given list.
    #
    # @param [ Symbol ] list The list to move the experiment to.
    #   Available options: :pending, :active, :completed
    #
    # @example Move a pending experiment to the active list
    #   experiment = Expierment.create!(name: 'Join now button')
    #   experiment.id # => 1
    #   experiment.status # => 'pending'
    #   experiment.move_to_list(:active) # => true
    #
    #   experiment.status # => 'active'
    #   Experiment.find_in_list(:pending, 1) # => nil
    #
    # @return [ Boolean ] True if successfully moved to the new list, false otherwise.
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
        add_to_completed_experiments_list
      end

      result = add_to_list(list)
      return false unless result

      remove_from_list(current_list)
      return true
    end

    # Save the experiment data.
    #
    # @example Edit the experiment name
    #   experiment = Expierment.create!(name: 'Join now button')
    #   experiment.name # => 1
    #   experiment.name # => 'Join now button'
    #
    #   experiment.name = 'Site footer'
    #   experiment.save
    #
    #   saved_experiment = Experiment.find(1)
    #   saved_experiment.name # => 'Site footer'
    #
    def save
      Lacmus.fast_storage.multi do
        Lacmus.fast_storage.zremrangebyscore self.class.list_key_by_type(@status), @id, @id
        Lacmus.fast_storage.zadd self.class.list_key_by_type(@status), @id, Marshal.dump(self.to_hash)
      end
    end

    # Activate an exeprtiment.
    # 
    # @return [ Boolean ] True on success, false on failure.
    #
    def activate!
      move_to_list(:active)
    end

    # Deactive an experiment, changing it's status to completed
    # and removing it from experiment_slots, making the slot empty.
    #
    # @return [ Boolean ] True on success, false on failure.
    #
    def deactivate!
      SlotMachine.remove_experiment_from_slot(@id)
      move_to_list(:completed)
    end

    # Permanently deletes an experiment.
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
      experiments_array   = []
      experiments_in_list = Lacmus.fast_storage.zrange list_key_by_type(list), 0, -1
      experiments_in_list.each do |experiment|
        experiment_hash = Marshal.load(experiment)
        experiments_array << new(experiment_hash)
      end
      experiments_array
    end

    def to_hash
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

    def add_to_completed_experiments_list
      Lacmus.fast_storage.zadd self.class.recent_completed_experiments_key, Time.now.utc.to_i, @id
    end

    def self.recent_completed_experiments
      key   = recent_completed_experiments_key
      score = Time.now.utc.to_i-MAX_RECENT_COMPLETED_EXPS

      res = Lacmus.fast_storage.multi do
        Lacmus.fast_storage.zremrangebyscore key, '-inf', score
        Lacmus.fast_storage.zrangebyscore key, score, '+inf'
      end
      res[1]
    end

    def kpi_timeline_data(kpi, is_control = false)
      Lacmus.fast_storage.zrange(self.class.timeline_kpi_key(@id, kpi, is_control), 0, -1, :with_scores => true)
    end

    def views_timeline_data(is_control = false)
      Lacmus.fast_storage.zrange(self.class.timeline_view_key(@id, is_control), 0, -1, :with_scores => true)
    end

    def conversion_timeline_data(kpi, is_control = false)
    	views = views_timeline_data(is_control)
    	kpis  = kpi_timeline_data(kpi, is_control)
    	return [] if views.empty? || kpis.empty?

    	sorted_views = views.sort {|x,y| x <=> y}.map {|i| i[1]}
    	sorted_kpis  = kpis.sort {|x,y| x <=> y}.map {|i| i[1]}

    	records_to_return = [sorted_views.size, sorted_kpis.size].min-1
    	sorted_views 			= sorted_views.last(records_to_return)
    	sorted_kpis  			= sorted_kpis.last(records_to_return)

    	conversion_data = []
    	records_to_return.times do |i|
    		conversion_data[i] = ((sorted_kpis[i] / sorted_views[i]) * 100).round(4)
    	end
    	conversion_data
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
      	mark_kpi_for_group(kpi, experiment_id, is_control)
      end
    end

    # Records a KPI event for the control group. Will increment
    # the KPI hit count and also the hourly count.
    #
    # @param [ String ] kpi The given name of the KPI to record
    # @param [ Integer ] experiment_id The id of the experiment
    # @param [ Boolean ] is_control True for control group, false otherwise
    # @param [ Integer ] amount The amount of the KPIs hit. Default is 1. 
    #                    For money related KPIs, this value would be the amount.
    #
    def self.mark_kpi_for_group(kpi, experiment_id, is_control = false, amount = 1)
      Lacmus.fast_storage.zincrby kpi_key(experiment_id, is_control), amount.to_i, kpi.to_s
      Lacmus.fast_storage.zincrby timeline_kpi_key(experiment_id, kpi, is_control), amount, current_time_in_hours.to_s
    end

    # Records an exposure event. Will increment the KPI hit count
    # and also the hourly count.
    #
    def self.track_experiment_exposure(experiment_id, is_control = false)
      Lacmus.fast_storage.incr exposure_key(experiment_id, is_control)
      Lacmus.fast_storage.zincrby timeline_view_key(experiment_id, is_control), 1, current_time_in_hours.to_s
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

    def self.current_time_in_hours
      Time.now.utc.to_i / 60 / 60
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

    def self.recent_completed_experiments_key
      "#{LACMUS_PREFIX}-recent-completed-exps"
    end

    def self.kpi_key(experiment_id, is_control = false)
      "#{LACMUS_PREFIX}-#{is_control}-kpis-#{experiment_id.to_s}"
    end

    def self.exposure_key(experiment_id, is_control = false)
      "#{LACMUS_PREFIX}-#{is_control}-counter-#{experiment_id.to_s}"
    end
  
    def self.timeline_kpi_key(experiment_id, kpi, is_control = false)
      "#{LACMUS_PREFIX}-#{is_control}-timeline-#{experiment_id.to_s}-#{kpi}"
    end

    def self.timeline_view_key(experiment_id, is_control = false)
    	"#{LACMUS_PREFIX}-#{is_control}-timeline-#{experiment_id.to_s}"
    end

  end # of Experiment

  class ExperimentHistoryItem

    def initialize(user_id, experiment_id, exposed_at_as_int, is_control)
      @user_id       = user_id.to_i
      @exposed_at    = Time.at(exposed_at_as_int)
      @experiment_id = experiment_id.to_i
      @control       = is_control
      @experiment    = Experiment.find(@experiment_id)
    end

  end # of ExperimentHistoryItem
end # of Lacmus