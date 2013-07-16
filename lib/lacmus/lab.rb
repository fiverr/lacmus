module Lacmus
	module Lab

		# Constants
		AMOUNT_OF_CONTROL_GROUPS = 1
		MAX_COOKIE_TIME = Time.now.utc.to_i + (60 * 60 * 24 * 365)

		def self.experiment_utils
			Lacmus::Experiment
		end

		def self.render_control_version(experiment_id, &block)
			empty_slot = user_belongs_to_empty_slot?
			control_group = user_belongs_to_control_group?

			if control_group || empty_slot
				if control_group
					track_control_group_exposure
				else
					Lacmus::Experiment.track_experiment_exposure(experiment_id)
				end
				
				yield(block) and return
			end
		end

		def self.render_experiment_version(experiment_id, &block)	
			empty_slot = user_belongs_to_empty_slot?
			control_group = user_belongs_to_control_group?

			return if control_group || empty_slot

			Lacmus::Experiment.track_experiment_exposure(experiment_id)
			yield(block)
		end


		def self.simple_experiment(experiment_id, control_version, experiment_version)
			empty_slot = user_belongs_to_empty_slot?
			control_group = user_belongs_to_control_group?

			if empty_slot || control_group
				Lacmus::Experiment.track_control_group_exposure if control_group
				return control_version
			end

			Lacmus::Experiment.track_experiment_exposure(experiment_id)
			return experiment_version
		end

		private 

		def self.user_belongs_to_control_group?
			slot_for_user == 0
		end

		def self.user_belongs_to_empty_slot?
			Lacmus::SlotMachine.get_experiment_id_from_slot(slot_for_user) == -1
		end

		# gets the user's slot in the experiment slot list,
		# having the first slot as the control group (equals to 0)
		def self.slot_for_user
			current_temp_user_id % (experiment_slots_count + AMOUNT_OF_CONTROL_GROUPS)
		end


		def self.build_tuid_cookie(temp_user_id)
			temp_user_id_cookie = {:value => "#{temp_user_id}", :expires => MAX_COOKIE_TIME}
		end

		# returns the temp user id from the cookies if present. If not,
		# it generates a new one and creates a cookie for it
		def self.current_temp_user_id
			uid = temp_user_id_cookie.value
			if uid.nil?
				uid = Lacmus::Utils.generate_tmp_user_id
				build_tuid_cookie(uid)
			end
			uid
		end

		def self.temp_user_id_cookie
			cookies['lacmus_tuid']
		end

		def self.experiment_cookie
			cookies['lacmus_exps']
		end

		def self.update_experiment_cookie(experiment_id)
			if experiment_cookie.nil?
				exposed_experiments_str = ''
			else
				exposed_experiments_str = experiment_cookie.value.to_s
			end
			experiment_cookie = {:value => "#{exposed_experiments_str};#{experiment_id.to_s}", :expires => MAX_COOKIE_TIME}
		end

		# this method generates a cache key to include in caches of the experiment host pages
		# it should be used to prevent a situation where experiments are exposed the same for all users
		# due to aciton caching.
		#
		# returns 0 for empty experiments and control group
		# returns experiment id for users who are selected for an active experiment
		def self.experiment_cache_key
			experiment_id = Lacmus::SlotMachine.get_experiment_id_from_slot(slot_for_user).to_i
			return '0' if [0,-1].include?(experiment_id)
			return experiment_id.to_s
		end
		
	end

end