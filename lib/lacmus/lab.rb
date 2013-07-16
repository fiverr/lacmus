module Lacmus
	module Lab
		# Constants
		AMOUNT_OF_CONTROL_GROUPS = 1

		def experiment_utils
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



# ------------------------------------------------------------------



		def self.simple_experiment(experiment_id, default_results, experiment_result)
			if should_render_experiment?(experiment_id)
				Lacmus::Experiment.track_exposure(experiment_id)
				return experiment_result	
			end

			if Lacmus::Experiment.control_group?
				Lacmus::Experiment.track_exposure(experiment_id)
			end

			default_results
		end

		private

		def self.build_tuid_cookie(temp_user_id)
			tuid_cookie = {:value => "#{temp_user_id}", :expires => max_cookie_time}
		end

		# returns the temp user id from the cookies if present. If not,
		# it generates a new one and creates a cookie for it
		def self.current_temp_user_id
			uid = tuid_cookie.value.to_i
			if uid.zero?
				uid = Lacmus::Utils.generate_tmp_user_id
				Lacmus::ClientStorage.build_tuid_cookie(uid)
			end
			uid
		end

		def self.store_exposed_experiment(experiment_id)
			if experiment_cookie.nil?
				exposed_experiments_str = ''
			else
				exposed_experiments_str = experiment_cookie.value.to_s
			end
			experiment_cookie = {:value => "#{exposed_experiments_str};#{experiment_id.to_s}", :expires => max_cookie_time}
		end

		def self.temp_user_id_cookie
			cookies['lacmus_tuid']
		end

		def self.experiment_cookie
			cookies['lacmus_exps']
		end

		def self.tuid_cookie
			temp_user_id_cookie
		end

		def self.experiment_cache_key
			get_group.to_s
		end

		def max_cookie_time
			Time.now.utc.to_i + (60 * 60 * 24 * 365)
		end
	end

end