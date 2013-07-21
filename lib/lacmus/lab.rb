module Lacmus
	module Lab

		# Constants
		MAX_COOKIE_TIME = Time.now.utc.to_i + (60 * 60 * 24 * 365)

		def self.render_control_version(experiment_id, &block)
			empty_slot = user_belongs_to_empty_slot?
			control_group = user_belongs_to_control_group?

			if control_group || empty_slot
				mark_experiment_view(experiment_id)				
				yield(block)
			end
		end

		def self.render_experiment_version(experiment_id, &block)	
			empty_slot = user_belongs_to_empty_slot?
			control_group = user_belongs_to_control_group?

			return if control_group || empty_slot

			mark_experiment_view(experiment_id)
			yield(block)
		end

		def self.simple_experiment(experiment_id, control_version, experiment_version)
			empty_slot = user_belongs_to_empty_slot?
			control_group = user_belongs_to_control_group?

			if empty_slot || control_group
				mark_experiment_view(experiment_id) if control_group
				return control_version
			end
			mark_experiment_view(experiment_id)
			
			return experiment_version
		end

		def self.user_belongs_to_control_group?
			slot_for_user == 0
		end

		def self.user_belongs_to_empty_slot?
			Lacmus::SlotMachine.get_experiment_id_from_slot(slot_for_user) == -1
		end

		def self.mark_kpi!(kpi)
			Lacmus::Experiment.mark_kpi!(kpi, experiment_id_from_cookie)
		rescue
			puts "#{__method__}: failed to mark_kpi for #{kpi}"
		end

		# this method generates a cache key to include in caches of the experiment host pages
		# it should be used to prevent a situation where experiments are exposed the same for all users
		# due to aciton caching.
		#
		# returns 0 for empty experiments and control group
		# returns experiment id for users who are selected for an active experiment
		def self.pizza_cache_key
			experiment_id = Lacmus::SlotMachine.get_experiment_id_from_slot(slot_for_user).to_i
			return '0' if [0,-1].include?(experiment_id)
			return experiment_id.to_s
		end

		private 

		def self.mark_experiment_view(experiment_id)
			Lacmus::Experiment.track_experiment_exposure(experiment_id)
			update_experiment_cookie(experiment_id)
		end

		# returns the temp user id from the cookies if present. If not,
		# it generates a new one and creates a cookie for it
		def self.current_temp_user_id
			uid = temp_user_id_cookie[:value]
			if uid.nil?
				uid = Lacmus::Utils.generate_tmp_user_id
				build_tuid_cookie(uid)
			end
			uid.to_i
		end

		# gets the user's slot in the experiment slot list,
		# having the first slot as the control group (equals to 0)
		def self.slot_for_user
			current_temp_user_id % Lacmus::SlotMachine.experiment_slots.count
		end

		# TODO: maybe we should also check that the experiment we get
		# here is actually active - if its not - we remove it from the cookie
		def self.experiment_id_from_cookie
			experiment_cookie[:value].to_i
		end

		def self.temp_user_id_cookie
			cookies['lacmus_tuid'] ||= {}
		end

		def self.experiment_cookie
			cookies['lacmus_exps'] ||= {}
		end

		def self.build_tuid_cookie(temp_user_id)
			cookies['lacmus_tuid'] = {:value => temp_user_id, :expires => MAX_COOKIE_TIME}
		end

		def self.update_experiment_cookie(experiment_id)
			unless experiment_cookie[:value].to_s == experiment_id.to_s
				cookies['lacmus_exps'] = {:value => experiment_id.to_s, :expires => MAX_COOKIE_TIME}
			end
		end
	end

end