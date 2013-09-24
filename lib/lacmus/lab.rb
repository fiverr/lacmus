# encoding: utf-8
module Lacmus
  # A mixin module that will automatically be included in your host application,
  # providing all the functionality needed to run a/b tests.
  #
  # * Rails application
  # Lacmus::Lab is included into ActionController::Base which will make it available
  # in any of your controllers, views and helpers.
  #
  # Before adding an experiment, it's best to add a few mark_kpi! events
  # around your application. Use mark_kpi for any event that you would
  # like to measure and compare it's performence.
  #
  # @example Mark the event of a new user created
  #
  #   class UsersController < ApplicationController
  #     def create
  #       @user = User.new(params[:user])
  #       if @user.save
  #         mark_kpi!('new_user')
  #       end
  #     end
  #   end
  #
  # There are 2 ways to run an experiment:
  # (1) Render text:
  #  Use to test a small change, possibly a string (can also store a boolean).
  #
  # @example Simple experiment for experiment id = 5, test a string
  #   simple_experiment(5, "default title", "experiment title")
  #
  # @example Simple experiment for experiment id = 6, test a boolean
  #   simple_experiment(6, false, true)
  #
  # (2) Render block:
  # Acts exactly the same as render text, but now it's possible
  # to execute an entire block.
  #
  # @example Render block for experiment id = 3
  #
  #   render_control_version(3) do
  #     "default title"
  #   end
  #
  #   render_experiment_version(3) do
  #     "experiment title"
  #   end
  #
  module Lab
    extend ActiveSupport::Concern   

    included do
      # When running under a rails application, we will set
      # all the following methods as helper method. This will
      # allow us to run tests in rails views and helpers.
      if Settings.running_under_rails?
        helper_method :render_control_version
        helper_method :render_experiment_version
        helper_method :mark_kpi!
        helper_method :simple_experiment
        helper_method :lacmus_cache_key
      end
    end

    # Set the user's cookies to expire based on the max_experiment_duration_in_days value.
    COOKIE_AGE_IN_SECONDS = (60 * 60 * 24 * Settings.max_experiment_duration_in_days)
    MAX_COOKIE_TIME       = Time.now.utc + COOKIE_AGE_IN_SECONDS

    # Execute a ruby block for control group users. The block will also
    # be executed if the users belongs to another experiment or to an
    # experiment that is not active anymore. This is done to assure that
    # something will be rendered to the user, regardless of his status.
    #
    # @example Render block for experiment id = 3
    #   render_control_version(3) do
    #     "default title"
    #   end
    #
    # @return [ Nil ] if the user belongs to the experiment.
    # @yieldreturn [ &block ] if the user doesn't belonged to the experiment.
    #
    def render_control_version(experiment_id, &block)
      return if user_belongs_to_experiment?(experiment_id)

      control_group = user_belongs_to_control_group?
      if control_group && should_mark_experiment_view?(experiment_id)
        mark_experiment_view(experiment_id)
      end

      @rendered_control_group = true
      yield(block)
    rescue Exception => e
      lacmus_logger "Failed to render control version.\n" <<
                    "experiment_id: #{experiment_id}, Exception: #{e.inspect}"
    end

    # Execute a ruby block for users belogned to this experiment only, assuming the
    # experiment is active.
    #
    # @example Render block for experiment id = 4
    #   render_experiment_version(4) do
    #     "experiment title"
    #   end
    #
    # @return [ Nil ] if experiment isn't active, user belongs to control group,
    #   user belongs to another experiment or user doesn't belong to any experiment.
    # @yieldreturn [ &block ] if user belongs to the experiment and it's active.
    #
    def render_experiment_version(experiment_id, &block)  
      return if @rendered_control_group
      return if user_belongs_to_empty_slot?
      return if user_belongs_to_control_group?
      return if !user_belongs_to_experiment?(experiment_id)

      if should_mark_experiment_view?(experiment_id)
        mark_experiment_view(experiment_id)
      end

      yield(block)
    rescue Exception => e
      lacmus_logger "Failed to render experiment version.\n" <<
                    "experiment_id: #{experiment_id}, Exception: #{e.inspect}"
    end

    # Render one of the given params: control_version or experiment_version
    # based on which group this user belongs to.
    #
    # experiment_version will be rendered only to users who belongs to the given
    # experiment_id, anyone else will receive the control_version.
    #
    # @param [ Integer ] experiment_id The experiment_id
    # @param [ Integer, Boolean, Symbol ] control_version The version to render for control users
    # @param [ Integer, Boolean, Symbol ] experiment_version The version to render for experiment users
    #
    # @example Simple experiment for experiment id = 6
    #   simple_experiment(6, "text for control group", "test for experiment group")
    #
    # @return The control_version param for control users
    #   and the experiment_version param for experiment users.
    #
    def simple_experiment(experiment_id, control_version, experiment_version)
      empty_slot = user_belongs_to_empty_slot?
      control_group = user_belongs_to_control_group?
      belongs_to_experiment = user_belongs_to_experiment?(experiment_id)

      if empty_slot || control_group || !belongs_to_experiment
        if control_group && should_mark_experiment_view?(experiment_id)
          mark_experiment_view(experiment_id)
        end
        return control_version
      end

      if should_mark_experiment_view?(experiment_id)
        mark_experiment_view(experiment_id)
      end
      return experiment_version
    rescue Exception => e
      lacmus_logger "Failed to render simple experiment.\n" <<
                    "experiment_id: #{experiment_id}, control_version: #{control_version}\n" <<
                    "experiment_version: #{experiment_version}\n" <<
                    "Exception: #{e.inspect}"
      control_version
    end

    # Mark the given kpi for all the experiments this user was exposed to.
    # User can mark multiple times the same kpi for a given experiment.
    #
    # @param [ String, Symbol ] kpi The new of the kpi
    #
    # @example mark_kpi!('new_user')
    #
    def mark_kpi!(kpi)
      Experiment.mark_kpi!(kpi, exposed_experiments_list_for_mark_kpi, user_belongs_to_control_group?)
    rescue Exception => e
      lacmus_logger "Failed to mark kpi: #{kpi}.\n" <<
                    "Exception message: #{e.inspect}\n" <<
                    "Exception backtrace: #{e.backtrace[0..10]}"
    end

    # Check if alternative user id was set for this user.
    #
    # @return [ Boolean ]
    #
    def has_alternative_user_id?
      cookie = user_data_from_cookie
      return false unless cookie
      return cookie.split('|').last == '1'
    rescue Exception => e
      lacmus_logger "Failed check if alternative_user_id is defined.\n" <<
                    "Exception message: #{e.inspect}\n" <<
                    "Exception backtrace: #{e.backtrace[0..10]}"
    end

    # Assosicate an alternative id with the lacmus user id.
    #
    # @note Read AsyncLab to understand why it helps to set it.
    # 
    def set_alternative_user_id(alternative_user_id)
      set_result = AlternativeUser.set_user_id(current_user_id, alternative_user_id)
      if set_result
        @uid_hash = build_tuid_cookie(current_user_id, 1)
      end
    rescue Exception => e
      lacmus_logger "Failed to set alternative user id for #{alternative_user_id}.\n" <<
                    "Exception message: #{e.inspect}\n" <<
                    "Exception backtrace: #{e.backtrace[0..10]}"
    end

    # Used to prevent a situation where experiments are not exposed properly
    # due to caching mechanism from the hosting application.
    #
    # @example Action caching in Rails
    #   class UsersController < ApplicationController
    #     caches_action :show, :cache_path => Proc.new { |c| c.show_cache_key }
    #
    #     def show_cache_key
    #       "users-show-#{lacmus_cache_key}"
    #     end
    #   end
    #
    # @return [ String ] The cache key based on which group the user belongs to.
    #
    def lacmus_cache_key
      return '0' unless @uid_hash || user_id_cookie

      experiment_id = SlotMachine.get_experiment_id_from_slot(slot_for_user).to_i
      return '0' if [0,-1].include?(experiment_id)
      return experiment_id.to_s
    rescue Exception => e
      lacmus_logger "Failed to get lacmus_cache_key\n" <<
                    "Exception message: #{e.inspect}\n" <<
                    "Exception backtrace: #{e.backtrace[0..10]}"
    end

    def available_lacmus_cache_keys
      default_values   = ['0', '-1']
      current_values   = SlotMachine.experiment_slot_ids
      recent_completed = Experiment.recent_completed_experiments
      [default_values, current_values, recent_completed].flatten.map {|i| i.to_s}.uniq
    rescue Exception => e
      lacmus_logger "Failed to get available_lacmus_cache_keys\n" <<
                    "Exception message: #{e.inspect}\n" <<
                    "Exception backtrace: #{e.backtrace[0..10]}"
    end

    private

    # Returns the experiment slot this user belongs to, starting from 0.
    # @note This is not the actual experiment id, just the slot.
    #
    # @example User belongs to the second slot, which holds experiment id = 3
    #   current_user_id = 1; SlotMachine.experiment_slot_ids = [0, 3]
    #
    #   Lacmus.slot_for_user # => 1
    #
    # @example User belongs to the first slot, which is the control group
    #   current_user_id = 2; SlotMachine.experiment_slot_ids = [0, 3]
    #
    #   Lacmus.slot_for_user # => 0
    #
    def slot_for_user
      current_user_id % SlotMachine.experiment_slot_ids.count
    end

    # Returns the experiment id this user belongs to.
    #
    # @example User belongs to control group
    #   Lacmus.experiment_for_user # => 0
    #
    # @example User belongs to empty slot
    #   Lacmus.experiment_for_user # => -1
    #
    # @example User belongs to experiment id = 5
    #   Lacmus.experiment_for_user # => 5
    #
    # @return [ Integer ] The experiment id for the given user.
    #
    def experiment_for_user
      @user_experiment ||= SlotMachine.get_experiment_id_from_slot(slot_for_user)
    end

    # Convenience method to check if user belongs to control group.
    #
    # @return [ Boolean ] True if belongs to control, false otherwise.
    #
    def user_belongs_to_control_group?
      slot_for_user == 0
    end

    # Convenience method to check if user belongs to given experiment_id.
    #
    # @param [ Integer ] experiment_id The experiment id to check against.
    #
    # @return [ Boolean ] True if belongs to the given experiment, false otherwise.
    #
    def user_belongs_to_experiment?(experiment_id)
      experiment_for_user == experiment_id
    end

    # Convenience method to check if user belongs to a slot which
    # doesn't hold an active experiment.
    #
    # @return [ Boolean ] True if belongs to empty slot, false otherwise.
    #
    def user_belongs_to_empty_slot?
      experiment_for_user == -1
    end

    # Returns if we should mark the experiment id for the given user.
    # User is only marked once for the experiments he belongs to.
    #
    # @note After experiment restart, the user will be marked again
    # once he is exposed to the experiment.
    #
    # @param [ Integer ] experiment_id The experiment id
    #
    # @return [ Boolean ] True if should mark the view, false otherwise.
    #
    def should_mark_experiment_view?(experiment_id)
      return false if !Experiment.active?(experiment_id)
      return true  if exposed_experiments.empty?

      if user_belongs_to_control_group?
        return true if !exposed_experiments_list.include?(experiment_id.to_i)
        return server_reset_requested?(experiment_id)
      else
        return true if experiment_for_user.to_i != current_experiment_id
        return true if user_belongs_to_experiment?(experiment_id) && server_reset_requested?(experiment_id)
        return false
      end
    end

    # Mark the experiment view by updating the user's cookie with the given
    # experiment_id, add the experiment to the user's experiment history log
    # and update the exposures count for the experiment.
    #
    # @param [ Integer ] experiment_id The experiment id
    #
    def mark_experiment_view(experiment_id)
      is_control = user_belongs_to_control_group?

      add_exposure_to_cookie(experiment_id, is_control)
      Experiment.track_experiment_exposure(experiment_id, is_control)
      ExperimentHistory.add(current_user_id, experiment_id)
    end

    # Checks if the user should be re-exposed to the given
    # experiment. This happens if the experiment was restarted
    # since the user's exposure.
    #
    # @example
    #   User was exposed at Wed Aug 14 09:08:32 UTC 2013
    #   Experiment was restarted at Wed Aug 14 11:08:32 UTC 2013
    #
    #     Lacmus.server_reset_requested?(3) # => true
    #
    # @param [ Integer ] experiment_id The experiment id
    #
    # @return [ Boolean ] True if reset requested, false otherwise.
    #
    def server_reset_requested?(experiment_id)
      exposed_at = exposed_experiments.select{|i| i.keys.first == experiment_id.to_s}[0][experiment_id.to_s]
      last_reset = SlotMachine.last_experiment_reset(experiment_id)

      return false if exposed_at.nil?
      return false if last_reset.nil?
      return last_reset.to_i > exposed_at.to_i
    end

    # Returns the user id. If we user id isn't cached nor we
    # can retrieve it from the cookie - we'll also generate
    # a new cookie and user id.
    #
    # @return [ Integer ] The user id
    #
    def current_user_id
      return cached_user_id      if cached_user_id
      return user_id_from_cookie if user_id_from_cookie

      new_user_id = Lacmus.generate_user_id
      @uid_hash = build_tuid_cookie(new_user_id)
      @uid_hash[:value].split('|').first.to_i
    end

    # Returns the cached user id
    #
    # @return [ Integer ] If cached user id was set.
    # @return [ Nil ]     If cached user id wasn't set.
    #
    def cached_user_id
      if defined?(__lcm__cached_user_id) && __lcm__cached_user_id
        __lcm__cached_user_id
      end
    end

    def user_id_from_cookie
      value = user_data_from_cookie
      value.split('|').first.to_i if value
    end

    # Retrieve the user data from the user's cookie.
    #
    # @example
    #   user_data_from_cookie # => '700|0'  
    #
    # @return [ String ]
    #
    def user_data_from_cookie
      if @uid_hash && @uid_hash[:value]
        return @uid_hash[:value]
      end
      
      uid_cookie = user_id_cookie
      if uid_cookie
        value = uid_cookie.is_a?(Hash) ? uid_cookie[:value] : uid_cookie
        return value
      end
    end

    # Returns the current experiment the user was exposed to,
    # based on his cookie.
    #
    # @note Control group users hold more than 1 experiment in
    #   their cookie because they're exposed to all available
    #   experiments, yet this method will only return the last
    #   experiment in their cookie.
    #
    # @example Experiment group user, belongs to experiment id = 3
    #   experiment_cookie: {:value => "e|3;29837462924", :expires => Wed Aug 14 09:48:09 UTC 2014}
    #   current_experiment_id # => 3
    #
    # @example Control group user, exposed to experiment ids 3 and 4
    #   experiment_cookie: {:value => "c|3;29837462924|4;29547432424", :expires => Wed Aug 14 09:48:09 UTC 2014}
    #   current_experiment_id # => 4
    #
    # @example User without a cookie
    #   experiment_cookie: {}
    #   current_experiment_id # => nil
    #
    # @return [ Nil ] If the user wasn't exposed to any experiment.
    # @return [ Integer ] The id of the last exposed experiment.
    #
    def current_experiment_id
      return unless experiment_data
      exposed_experiments.last.keys.last.to_i
    end

    # Returns the experiment cookie
    #
    # @example Control group user, exposed to experiment id = 3
    #   at 1376475145 (Wed Aug 14 10:12:38 UTC 2013 as int)
    #
    #   experiment_cookie_value # => "c|3;1376475145"
    #
    # @return [ String ] The experiments this user was exposed to (and when)
    #
    # def experiment_cookie_value
    #   cookie_value = experiment_data
    #   cookie_value.is_a?(Hash) ? cookie_value[:value] : cookie_value
    # end

    # Returns the value of the user id cookie.
    #
    # @note When the cookie is already set, the cookie is part of
    #   the request and we're going to get the value as string.
    #   But, if we created the cookie within this request, this method
    #   will return a hash containg the cookie's value.
    #   Because of that, it's best not to call this method directly,
    #   but to current_user_id which handles both end cases.
    #
    # @example Cookie sent in request
    #   user_id_cookie # => "13231"
    #
    # @example Cookie was created in this request
    #   user_id_cookie # => {:value => "13231", :expires => Wed Aug 14 09:48:09 UTC 2014}
    #
    # @return [ String ] If the cookie was sent in the request.
    # @return [ Hash ] If the cookie was just created.
    #
    def user_id_cookie
      cookies['lc_tuid']
    end

    # Generate the user id cookie with the given user_id.
    # The cookie's value is seperated by '|'. The first part
    # represents the user id and the second represents whether
    # alternative user id was set.
    #
    # @note Read AsyncLab for more info on alternative user id usage.
    #
    # @param [ Integer ] user_id.
    #
    # @return [ Hash ] The generated cookie.
    #
    def build_tuid_cookie(user_id, alternative_user_id_status = 0)
      cookies['lc_tuid'] = {:value => "#{user_id}|#{alternative_user_id_status}", :expires => MAX_COOKIE_TIME}
    end

    # Returns the value of the user's experiment cookie.
    #
    # @note When the cookie is already set, the cookie is part of
    #   the request and we're going to get the value as string.
    #   But, if we created the cookie within this request, this method
    #   will return a hash containg the cookie's value.
    #   Because of that, it's best not to call this method directly,
    #   but to experiment_cookie_value which handles both end cases.
    #
    # @example Cookie sent in request
    #   experiment_cookie # => "c|3;1376475145"
    #
    # @example Cookie was created in this request
    #   experiment_cookie # => {:value => "c|3;29837462924", :expires => Wed Aug 14 09:48:09 UTC 2014}
    #
    # @return [ String ] If the cookie was sent in the request.
    # @return [ Hash ] If the cookie was just created.
    #
    # @todo was experiment_cookie
    def experiment_data_from_cookie
      cookie_data = cookies['lc_xpmnt']
      cookie_data.is_a?(Hash) ? cookie_data[:value] : cookie_data
    end

    def experiment_data_from_redis
      Lacmus::fast_storage.get redis_experiment_data_key(current_user_id)
    end

    def experiment_data
      return experiment_data_from_cookie if use_cookie_storage?
      experiment_data_from_redis
    end

    def set_experiment_data(cookie_hash)
      if use_cookie_storage?
        cookies['lc_xpmnt'] = cookie_hash
      end

      if use_redis_storage?
        key = redis_experiment_data_key(current_user_id)
        Lacmus::fast_storage.setex key, COOKIE_AGE_IN_SECONDS, cookie_hash[:value]
      end
    end

    def redis_experiment_data_key(user_id)
      "#{LACMUS_PREFIX}-exp-data-#{user_id}"
    end

    def use_cookie_storage?
      return false unless defined?(cookies)
      return false if cookies.nil?
      ['auto', 'cookie'].include?(Settings.experiment_data_store)
    end

    def use_redis_storage?
      ['auto', 'redis'].include?(Settings.experiment_data_store)
    end

    # Returns the group prefix for the user based on
    # which group/experiment he belongs to.
    #
    # @return [ String ] The group prefix
    #
    def group_prefix
      return 'c' if user_belongs_to_control_group?
      return 'x' if user_belongs_to_empty_slot?
      return 'e'
    end

    # Returns whether the user's experiment cookie contains
    # the control group prefix. 
    #
    # @return [ Boolean ] True if contains the prefix, false otherwise.
    #
    def control_group_prefix?
      value = experiment_data
      return false if value.nil?

      cookie_prefix = value.split('|')[0]
      return cookie_prefix == 'c'
    end

    # Returns an array containing all the experiments the user
    # was exposed to and when.
    #
    # @example User exposed to experiment id = 234 at 2013-07-25 13:00:36 +0300
    #   exposed_experiments # => [{'234' => 2013-07-25 13:00:36 +0300}]
    #
    # @return [ Array<Hash> ] Array of hashes, where keys represent the experiment id
    #   and values reprsent the exposure time.
    #
    def exposed_experiments
      experiments_array = []
      if experiment_data
        raw_experiment_array = experiment_data.split("|")[1..-1] # first element represents the group_prefix
        raw_experiment_array.collect!{|pair| pair.split(";").collect!{|val|val.to_i}}
      else
        return []
      end

      raw_experiment_array.each do |experiment_id, exposed_at_as_int|
        experiments_array << {experiment_id.to_s => Time.at(exposed_at_as_int.to_i)}
      end
      experiments_array
    end

    # Returns an array containings all experiment ids the user
    # was exposed to.
    #
    # @example User exposed to experiment id = 234 at 2013-07-25 13:00:36 +0300
    #   exposed_experiments_list # => [234]
    #
    # @return [ Array<Integer> ] Array of integers representing all exposed experiment ids.
    #
    def exposed_experiments_list
      exposed_experiments.collect{|i| i.keys}.flatten.collect{|i| i.to_i}
    end

    # Returns a list of all experiment ids that the user was exposed to
    # and should be marked when calling mark_kpi! method.
    #
    # @note Check should_mark_kpi_for_experiment? method to understand why
    #   we can't simply to return all the exposed experiments.
    #
    # @example User exposed to experiment ids 8, 13, 15
    #   exposed_experiments_list_for_mark_kpi # => [8, 15]
    #
    # @return [ Array<Integer> ] Array of integers representing experiment ids that should be marked.
    #
    def exposed_experiments_list_for_mark_kpi
      experiment_ids = []
      exposed_experiments.each do |experiment|
        experiment_id = experiment.keys.first.to_i
        if should_mark_kpi_for_experiment?(experiment_id)
          experiment_ids << experiment_id
        end
      end
      experiment_ids
    end

    # Check whether we should mark kpi for the given experiment_id.
    # If the experiment is no longer active or restarted after
    # the user exposure - we return false.
    #
    # @example User exposed to experiment id = 234 at Wed Aug 14 13:37:36 UTC 2013
    #   and it was restarted at Wed Aug 14 15:23:16 UTC 2013
    #
    #   should_mark_kpi_for_experiment?(234) # => false
    #
    # @return [ Boolean ] True if should mark kpi, false otherwise.
    #     
    def should_mark_kpi_for_experiment?(experiment_id)
      experiment_id = experiment_id.to_i
      return false if !Experiment.active?(experiment_id)
      return false if server_reset_requested?(experiment_id)
      return true
    end

    # Update the user's experiment cookie with the new exposed
    # experiment_id. The experiment cookie behave a bit different
    # for control group users and experiment group users.
    #
    # Control group users: Cookie can hold multiple experiments,
    # as many as active experiments we have.
    #
    # Experiment group users: Cookie will hold the current experiment
    # he's belonged to.
    # 
    # @example Control group user, already exposed to experiment id 3110 at 1375362524
    #
    #   add_exposure_to_cookie(3111, true)
    #     => {:value => "c|3110;1375362524|3111;1375362526", :expires => Wed Aug 14 09:48:09 UTC 2014}
    #
    # @example Experiment group user
    #
    #   add_exposure_to_cookie(3111, false)
    #     => {:value => "e|3111;1375362526", :expires => Wed Aug 14 09:48:09 UTC 2014}
    #
    # @return [ Hash ] The content of the updated user's experiment cookie
    #
    def add_exposure_to_cookie(experiment_id, is_control = false)
      new_data = "#{experiment_id};#{Time.now.utc.to_i}"

      if cookies['lc_xpmnt'] && exposed_experiments_list.include?(experiment_id.to_i)
        remove_exposure_from_cookie(experiment_id)
      end

      # control_group_prefix? is checked because user can switch groups
      # when experiment_slots is changed. If user was belonged to experiment group
      # and now is control - we need to recreate his cookie.
      if is_control && cookies['lc_xpmnt'] && control_group_prefix?
        data = "#{experiment_data}|#{new_data}"
      else
        data = "#{group_prefix}|#{new_data}"
      end
      set_experiment_data({:value => data, :expires => MAX_COOKIE_TIME})
    end

    # Remove the given experiment_id from the user's experiment
    # cookie if present.
    #
    # @example
    #   cookies['lc_xpmnt'] = {:value => "e|3111;1375362526", :expires => Wed Aug 14 09:48:09 UTC 2014}
    #   remove_exposure_from_cookie(3111)
    #     => {:value => "e", :expires => Wed Aug 15 10:41:23 UTC 2014}
    #
    # @return [ Hash ] The content of the updated user's experiment cookie
    #
    def remove_exposure_from_cookie(experiment_id)
      return unless experiment_data
      exps_array          = experiment_data.split('|')
      new_cookie_value    = exps_array.delete_if {|i| i.start_with?("#{experiment_id};")}
      new_cookie_value    = new_cookie_value.join('|')
      set_experiment_data({:value => new_cookie_value, :expires => MAX_COOKIE_TIME})
    end

    # Logger used to print lacmus errors.
    #
    def lacmus_logger(log)
      if Settings.running_under_rails?
        Rails.logger.error log
      else
        puts log
      end
    end

  end # of Lab
end # of Lacmus