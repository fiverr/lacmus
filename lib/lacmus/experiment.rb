require_relative 'settings'
require_relative 'fast_storage'

module Lacmus
	module Experiment

		# Class variables
		@@web_admin_prefs = {}
		@@web_prefs_last_loaded_at = nil

		def self.expose_experiment(experiment_id)
			return unless experiment_active?(experiment_id)

			if user_exposed_to_experiment?(experiment_id)
				track_exposure(experiment_id)
			end
		end

		def self.active_experiments
			Lacmus.fast_storage.smembers active_experiments_key
		end

		def self.experiment_active?(experiment_id)
			Lacmus.fast_storage.sismember active_experiments_key, experiment_id
		end

		def self.web_admin_prefs
			if @@web_prefs_last_loaded_at.nil? || @@web_prefs_last_loaded_at < (Time.now - 60)
				load_web_admin_prefs
			end

			@@web_admin_prefs
		end

		private

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

		def self.user_exposed_to_experiment?(experiment_id)
			exposed_experiments.include?(experiment_id)
		end

		def self.exposed_experiments
			return [] unless Lacmus.client_storage.experiment_cookie
			Lacmus.client_storage.experiment_cookie.split(";")
		end

		def self.track_control_group_exposure
			track_experiment_exposure(0)
		end

		def self.track_experiment_exposure(experiment_id)
			Lacmus.fast_storage.incr view_counter_key(experiment_id)
		end

		def self.exposed_counter(experiment_id)
			Lacmus.fast_storage.incr view_counter_key(experiment_id, group)
		end

		def self.experiment_slots_count
			Lacmus::SlotMachine.experiment_slots.count
		end

		def self.load_web_admin_prefs
			@@web_prefs_last_loaded_at = Time.now
			@@web_admin_prefs = Marshal.load(Lacmus.fast_storage.get web_admin_prefs_key)
		end

		# ------------------------------------------------

		def self.active_experiments_key
			Lacmus::SlotMachine.list_key_by_type(:active)
		end

		def self.view_counter_key(experiment_id)
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-counter-#{experiment_id.to_s}"
		end

		def self.web_admin_prefs_key
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-web-admin-prefs"
		end

	end
end