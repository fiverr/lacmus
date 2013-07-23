require_relative 'slot_machine'
require_relative 'experiment'
require_relative 'utils'

module Lacmus
	module Lab

		def self.included(base)
    	base.class_eval do
      	extend ClassMethods
      	include InstanceMethods
    	end
  	end

  	module ClassMethods
  	end

  	module InstanceMethods
			# Constants
			MAX_COOKIE_TIME = Time.now.utc + (60 * 60 * 24 * 365)

			def render_control_version(experiment_id, &block)
				return if user_belongs_to_experiment?(experiment_id)

				mark_experiment_view(experiment_id)	if user_belongs_to_control_group?
				@rendered_control_group = true
				yield(block)
			end

			def render_experiment_version(experiment_id, &block)	
				return if @rendered_control_group
				return if user_belongs_to_empty_slot?
				return if user_belongs_to_control_group?
				return if !user_belongs_to_experiment?(experiment_id)

				mark_experiment_view(experiment_id)
				yield(block)
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
			end

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

			def mark_kpi!(kpi)
				Lacmus::Experiment.mark_kpi!(kpi, current_experiment)
			rescue
				puts "#{__method__}: failed to mark_kpi for #{kpi}"
			end

			# this method generates a cache key to include in caches of the experiment host pages
			# it should be used to prevent a situation where experiments are exposed the same for all users
			# due to aciton caching.
			#
			# returns 0 for empty experiments and control group
			# returns experiment id for users who are selected for an active experiment
			def pizza_cache_key
				experiment_id = Lacmus::SlotMachine.get_experiment_id_from_slot(slot_for_user).to_i
				return '0' if [0,-1].include?(experiment_id)
				return experiment_id.to_s
			end

			private 

			# Update the user's cookie with the current experiment
			# he belongs to and increment the experiment's views.
			# This should only happen once per user, so views
			# are actually unique views.
			def mark_experiment_view(experiment_id)
				return if current_experiment.to_i == experiment_id.to_i

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

			# gets the user's slot in the experiment slot list,
			# having the first slot as the control group (equals to 0)
			def slot_for_user
				current_temp_user_id % Lacmus::SlotMachine.experiment_slots.count
			end

			# TODO: maybe we should also check that the experiment we get
			# here is actually active - if its not - we remove it from the cookie
			def temp_user_id_cookie
				cookies['lacmus_tuid']
			end

			def experiment_cookie
				cookies['lacmus_exps']
			end

			def build_tuid_cookie(temp_user_id)
				cookies['lacmus_tuid'] = {:value => temp_user_id, :expires => MAX_COOKIE_TIME}
			end

			def update_experiment_cookie(experiment_id)
				Lacmus::ExperimentHistory.log_experiment(experiment_id, Time.now.utc)
				cookies['lacmus_exps'] = {:value => experiment_id.to_s, :expires => MAX_COOKIE_TIME}	
			end
		end
	end


end