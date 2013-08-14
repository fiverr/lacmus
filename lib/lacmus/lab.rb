require 'lacmus/settings'
require 'lacmus/experiment'
require 'lacmus/slot_machine'

module Lacmus
	# A mixin module that should be included in your host application, providing all
	# the functionality needed to run a/b tests.
	#
	# * Rails application
	# Including lacmus in any of the application's controllers in order
	# to start running tests. It's best to include into ApplicationController
	# so lacmus will be available to the entire app. Once integrated, you can start
	# running experiments anywhere in your controllers, views and helpers.
	#
	# @example Integrate lacmus in a Rails app 
	# 	class ApplicationController < ActionController::Base
	# 		include Lacmus::Lab
	# 	end
	#
	# Before adding an experiment, it's best to add a few mark_kpi! events
	# around your application. Use mark_kpi for any event that you would
	# like to measure, and compare it's performence.
	#
	# @example Mark the event of new user created
	# 	class UsersController < ApplicationController
	# 		def create
	# 			@user = User.new(params[:user])
	# 			if @user.save
	# 				mark_kpi!('new_user')
	# 			end
	# 		end
	# 	end
	#
	# There are 2 ways to run an experiment:
	# (1) Render text:
	#  Use to test a small change, possibly a string (can also store a boolean).
	#
	# @example Simple experiment for experiment id = 5, test a string
	# 	simple_experiment(5, "default title", "experiment title")
	#
	# @example Simple experiment for experiment id = 6, test a boolean
	# 	simple_experiment(6, false, true)
	#
	# (2) Render block:
	# Acts exactly the same as render text, but now it's possible
	# to execute an entire block.
	#
	# @example Render block for experiment id = 3
	# 	render_control_version(3) do
	# 		"default title"
	# 	end
	#
	# 	render_experiment_version(3) do
	#			"experiment title"
	# 	end
	#
	module Lab

		def self.included(base)
    	base.class_eval do
      	extend ClassMethods
      	include InstanceMethods

      	# When running under a rails application, we will set
      	# all the following methods as helper method. This will
      	# allow us to run tests in rails views and helpers.
      	if Settings.running_under_rails?
      		base.helper_method :render_control_version
      		base.helper_method :render_experiment_version
      		base.helper_method :mark_kpi!
      		base.helper_method :simple_experiment
      		base.helper_method :lacmus_cache_key
      	end
    	end
  	end

  	module ClassMethods
  	end

  	module InstanceMethods

			# Set the user's cookies to expire after 1 year.
			MAX_COOKIE_TIME = Time.now.utc + (60 * 60 * 24 * 365)

			# Execute a ruby block for control group users. The block will also
			# be executed if the users belongs to another experiment or to an
			# experiment that is not active anymore. This is done to assure that
			# something will be rendered to the user, regardless of his status.
			#
			# @example Render block for experiment id = 3
			# 	render_control_version(3) do
			# 		"default title"
			# 	end
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
				lacmus_logger "#{__method__}: Failed to render control version\n" <<
						 					"experiment_id: #{experiment_id}, Exception: #{e.inspect}"
			end

			# Execute a ruby block for users belogned to this experiment only, assuming the
			# experiment is active.
			#
			# @example Render block for experiment id = 4
			# 	render_experiment_version(4) do
			# 		"experiment title"
			# 	end
			#
			# @return [ Nil ] if experiment isn't active, user belongs to control group,
			# 	user belongs to another experiment or user doesn't belong to any experiment.
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
				lacmus_logger "#{__method__}: Failed to render experiment version\n" <<
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
			# 	simple_experiment(6, "text for control group", "test for experiment group")
			#
			# @return The control_version param for control users
			# 	and the experiment_version param for experiment users.
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
				lacmus_logger "#{__method__}: Failed to render simple experiment\n" <<
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
				lacmus_logger "#{__method__}: Failed to mark kpi: #{kpi}\n" <<
											"Exception message: #{e.inspect}\n" <<
											"Exception backtrace: #{e.backtrace[0..10]}"
			end

			# Used to prevent a situation where experiments are not exposed properly
			# due to caching mechanism from the hosting application.
			#
			# @example Action caching in Rails
			# 	class UsersController < ApplicationController
			# 		caches_action :show, :cache_path => Proc.new { |c| c.show_cache_key }
			#
			# 		def show_cache_key
			# 			"users-show-#{lacmus_cache_key}"
			# 		end
			# 	end
			#
			# @return [ String ] The cache key based on which group the user belongs to.
			#
			def lacmus_cache_key
				return '0' unless @uid_hash || user_id_cookie

				experiment_id = SlotMachine.get_experiment_id_from_slot(slot_for_user).to_i
				return '0' if [0,-1].include?(experiment_id)
				return experiment_id.to_s
			rescue Exception => e
				lacmus_logger "#{__method__}: Failed to get lacmus_cache_key, e: #{e.inspect}"
			end

			private

			# Returns the experiment slot this user belongs to, starting from 0.
			# @note This is not the actual experiment id, just the slot.
			#
			# @example User belongs to the second slot, which holds experiment id = 3
			# 	current_user_id = 1; SlotMachine.experiment_slot_ids = [0, 3]
			#
			# 	Lacmus.slot_for_user # => 1
			#
			# @example User belongs to the first slot, which is the control group
			# 	current_user_id = 2; SlotMachine.experiment_slot_ids = [0, 3]
			#
			# 	Lacmus.slot_for_user # => 0
			#
			def slot_for_user
				current_user_id % SlotMachine.experiment_slot_ids.count
			end

			# Returns the experiment id this user belongs to.
			#
			# @example User belongs to control group (experiment id = 0)
			# 	Lacmus.experiment_for_user # => 0
			#
			# @example User belongs to empty slot (experiment id = -1)
			# 	Lacmus.experiment_for_user # => -1
			#
			# @example User belongs to experiment (experiment id = 5)
			# 	Lacmus.experiment_for_user # => 5
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
			# User is only marked once for each experiment he is exposed and
			# belongs to.
			#
			# based on whether 
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

			# Update the user's cookie with the current experiment
			# he belongs to and increment the experiment's views.
			def mark_experiment_view(experiment_id)
				is_control = user_belongs_to_control_group?

				add_exposure_to_cookie(experiment_id, is_control)
				Experiment.track_experiment_exposure(experiment_id, is_control)
				ExperimentHistory.add(current_user_id, experiment_id)
			end

			# TODO: refactor exposed_at variable
			def server_reset_requested?(experiment_id)
				exposed_at = exposed_experiments.select{|i| i.keys.first == experiment_id.to_s}[0][experiment_id.to_s]
				last_reset = SlotMachine.last_experiment_reset(experiment_id)

				return false if exposed_at.nil?
				return false if last_reset.nil?
				return last_reset.to_i > exposed_at.to_i
			end

			# returns the user id from the cookies if present. If not,
			# it generates a new one and creates a cookie for it
			def current_user_id
				return @uid_hash[:value] if @uid_hash && @uid_hash[:value]
				
				uid_cookie = user_id_cookie
				
				return uid_cookie.to_i if uid_cookie && uid_cookie.respond_to?(:to_i) 
				return uid_cookie[:value].to_i if uid_cookie && uid_cookie.respond_to?(:keys) 

				new_user_id = Lacmus.generate_user_id
				@uid_hash = build_tuid_cookie(new_user_id)
				@uid_hash[:value]
			end

			def current_experiment_id
				return unless experiment_cookie
				exposed_experiments.last.keys.last.to_i
			end

			def experiment_cookie_value
				cookie_value = experiment_cookie
				cookie_value.is_a?(Hash) ? cookie_value[:value] : cookie_value
			end

			def user_id_cookie
				cookies['lc_tuid']
			end

			def experiment_cookie
				cookies['lc_xpmnt']
			end

			def group_prefix
				return "c" if user_belongs_to_control_group?
				return "x" if user_belongs_to_empty_slot?
				return "e"
			end

			def control_group_prefix?
				value = experiment_cookie_value
				return false if value.nil?

				cookie_prefix = value.split("|")[0]
				return cookie_prefix == "c"
			end

			# returns hash {'234' => 2013-07-25 13:00:36 +0300}
			# the exposed experiments cookie has a first cell that hints of the user's
			# slot group (control, empty slot or experiment) followed by the experiments the user was exposed to
			#
			# === Example for cookie: [c|234;29837462924]
			def exposed_experiments
				experiments_array = []
				if experiment_cookie_value
					raw_experiment_array = experiment_cookie_value.split("|")[1..-1] # first element represents the group_prefix
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
			def exposed_experiments_list
				exposed_experiments.collect{|i| i.keys}.flatten.collect{|i| i.to_i}
			end

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
			# @example:
			# 	Control group user, exposed to experiment id 3110 at 1375362524
			# 	and was exposed to experiment id 3111 at 1375362526
			# 		=> "c|3110;1375362524|3111;1375362526"
			#
			# @example:
			# 	Experiment group user, exposed to experiment id 3112 at 1375362745
			# 		=> "e|3112;1375362745"
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
					data = "#{experiment_cookie_value}|#{new_data}"
				else
					data = "#{group_prefix}|#{new_data}"
				end
				cookies['lc_xpmnt'] = {:value => data, :expires => MAX_COOKIE_TIME}	
			end

			def remove_exposure_from_cookie(experiment_id)
				return unless experiment_cookie_value
				exps_array 			 		= experiment_cookie_value.split('|')
				new_cookie_value 		= exps_array.delete_if {|i| i.start_with?("#{experiment_id};")}
				new_cookie_value    = new_cookie_value.join('|')
				cookies['lc_xpmnt'] = {:value => new_cookie_value, :expires => MAX_COOKIE_TIME}	
			end
			
			def build_tuid_cookie(user_id)
				cookies['lc_tuid'] = {:value => user_id, :expires => MAX_COOKIE_TIME}
			end

			def lacmus_logger(log)
				if Settings.running_under_rails?
					Rails.logger.error log
				else
					puts log
				end
			end

		end # of InstanceMethods

	end # of Lab
end # of Lacmus