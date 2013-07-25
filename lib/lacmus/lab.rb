require_relative 'slot_machine'
require_relative 'experiment'
require_relative 'utils'

module Lacmus
	module Lab

		def self.included(base)
    	base.class_eval do
      	extend ClassMethods
      	include InstanceMethods

      	if $has_rails
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

			# Constants
			MAX_COOKIE_TIME = Time.now.utc + (60 * 60 * 24 * 365)

			def render_control_version(experiment_id, &block)
				return if user_belongs_to_experiment?(experiment_id)

				mark_control_view(experiment_id)	if user_belongs_to_control_group?
				@rendered_control_group = true
				yield(block)
			rescue Exception => e
				puts "#{__method__}: Failed to render control version\n" <<
						 "experiment_id: #{experiment_id}, Exception: #{e.inspect}"
			end

			def render_experiment_version(experiment_id, &block)	
				return if @rendered_control_group
				return if user_belongs_to_empty_slot?
				return if user_belongs_to_control_group?
				return if !user_belongs_to_experiment?(experiment_id)

				mark_experiment_view(experiment_id)
				yield(block)
			rescue Exception => e
				puts "#{__method__}: Failed to render experiment version\n" <<
						 "experiment_id: #{experiment_id}, Exception: #{e.inspect}"
			end

			def simple_experiment(experiment_id, control_version, experiment_version)
				empty_slot = user_belongs_to_empty_slot?
				control_group = user_belongs_to_control_group?
				belongs_to_experiment = user_belongs_to_experiment?(experiment_id)

				if empty_slot || control_group || !belongs_to_experiment
					if control_group && user_belongs_to_experiment?(experiment_id)
						mark_experiment_view(experiment_id)
					end
					return control_version
				end

				mark_experiment_view(experiment_id)
				return experiment_version
			rescue Exception => e
				puts "#{__method__}: Failed to render simple experiment\n" <<
						 "experiment_id: #{experiment_id}, control_version: #{control_version}\n" <<
						 "experiment_version: #{experiment_version}\n" <<
						 "Exception: #{e.inspect}"
			end

			def mark_kpi!(kpi)
				Lacmus::Experiment.mark_kpi!(kpi, current_experiment)
			rescue Exception => e
				puts "#{__method__}: Failed to mark kpi: #{kpi}, e: #{e.inspect}"
			end

			# this method generates a cache key to include in caches of the experiment host pages
			# it should be used to prevent a situation where experiments are exposed the same for all users
			# due to aciton caching.
			#
			# returns 0 for empty experiments and control group
			# returns experiment id for users who are selected for an active experiment
			def lacmus_cache_key
				experiment_id = Lacmus::SlotMachine.get_experiment_id_from_slot(slot_for_user).to_i
				return '0' if [0,-1].include?(experiment_id)
				return experiment_id.to_s
			rescue Exception => e
				puts "#{__method__}: Failed to get lacmus_cache_key, e: #{e.inspect}"
			end

			private

			def user_belongs_to_control_group?
				slot_for_user == 0
			end

			def experiment_for_user
				@user_experiment ||= Lacmus::SlotMachine.get_experiment_id_from_slot(slot_for_user)
			end

			def user_belongs_to_experiment?(experiment_id)
				experiment_for_user == experiment_id
			end

			def user_belongs_to_empty_slot?
				experiment_for_user == -1
			end

			# Update the user's cookie with the current experiment
			# he belongs to and increment the experiment's views.
			# This should only happen once per user, so views
			# are actually unique views.
			def mark_experiment_view(experiment_id)
				if should_update_experiment_cookie?(experiment_id)
					update_experiment_cookie(experiment_id)
				end

				if experiment_for_user.to_i == experiment_id.to_i				
					Lacmus::Experiment.track_experiment_exposure(experiment_id)
				end
			end

			def should_update_experiment_cookie?(experiment_id)
				return true if current_experiment.blank?
				return true if current_experiment != experiment_for_user.to_i
				return true if server_reset_requested?(experiment_id)
			end

			# TODO: finish this
			def server_reset_requested?(experiment_id)
				# Lacmus::SlotMachine
				# Lacmus::Experiment.new(experiment_id)
				# exposed_experiments
			end

			def mark_control_view(experiment_id)
				return unless current_experiment.blank?
				
				update_experiment_cookie(experiment_id)
				Lacmus::Experiment.track_experiment_exposure(experiment_id)
			end

			# returns the temp user id from the cookies if present. If not,
			# it generates a new one and creates a cookie for it
			def current_temp_user_id
				return @uid_hash[:value] if @uid_hash && @uid_hash[:value]
				
				uid_cookie = temp_user_id_cookie
				
				return uid_cookie.to_i if uid_cookie && uid_cookie.respond_to?(:to_i) 
				return uid_cookie[:value].to_i if uid_cookie && uid_cookie.respond_to?(:keys) 

				new_tmp_id = Lacmus::Utils.generate_tmp_user_id
				@uid_hash = build_tuid_cookie(new_tmp_id)
				@uid_hash[:value]
			end

			def current_experiment
				return unless experiment_cookie
				return experiment_cookie.to_i if experiment_cookie.respond_to?(:to_i) 
				return experiment_cookie[:value].to_i if experiment_cookie.respond_to?(:keys) 
			end

			def exposed_at
				Time.at(exposure_cookie.to_i)
			end

			# gets the user's slot in the experiment slot list,
			# having the first slot as the control group (equals to 0)
			def slot_for_user
				current_temp_user_id % Lacmus::SlotMachine.experiment_slot_ids.count
			end

			# TODO: maybe we should also check that the experiment we get
			# here is actually active - if its not - we remove it from the cookie
			def temp_user_id_cookie
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

			# returns hash {'234' => 2013-07-25 13:00:36 +0300}
			# the exposed experiments cookie has a first cell that hints of the user's
			# slot group (control, empty slot or experiment) followed by the experiments the user was exposed to
			#
			# == Example for cookie: [c|234;29837462924]
			def exposed_experiments
				experiments_hash = {}
				if cookies['lc_xpmnt']
					raw_experiment_array = cookies['lc_xpmnt'].split("|").collect{|pair| pair.split(";").collect{|val|val.to_i}}
				else
					[]
				end

				result.each do |experiment_id, exposed_at_as_int|
					experiments_hash.merge!({experiment_id.to_s => Time.at(exposed_at_as_int.to_i)})
				end
				experiments_hash
			end

			def add_exposure_to_cookie(experiment_id)
				new_data = "#{experiment_id};#{Time.now.utc.to_i}"
				if cookies['lc_xpmnt']
					data = "#{cookies['lc_xpmnt']}|#{new_data}"
				else
					data = "#{group_prefix}|#{new_data}"
				end
				cookies['lc_xpmnt'] = {:value => data, :expires => MAX_COOKIE_TIME}	
			end
			
			def build_tuid_cookie(temp_user_id)
				cookies['lc_tuid'] = {:value => temp_user_id, :expires => MAX_COOKIE_TIME}
			end

			# set the experiment that was exposed to the user, and when it was exposed
			def update_experiment_cookie(experiment_id)
				Lacmus::ExperimentHistory.log_experiment(experiment_for_user, Time.now.utc)
				add_exposure_to_cookie(experiment_id)
			end

		end # of InstanceMethods

	end # of Lab
end # of Lacmus