require_relative 'settings'
require_relative 'fast_storage'

module Lacmus
	module Experiment

		# Constants
		AMOUNT_OF_CONTROL_GROUPS = 1

		# Class variables
		@@web_admin_prefs = {}
		@@web_prefs_last_loaded_at = nil

		def self.expose_experiment(experiment_id)
			return unless experiment_active?(experiment_id)

			if user_never_exposed?(experiment_id)
				track_exposure(experiment_id)
			end
		end

		def self.active_experiments
			Lacmus.fast_storage.smembers active_experiments_key
		end

		# def self.control_group
		# 	get_group.to_i.zero?
		# end

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
				Lacmus::ClientStorage.build_tuid_cookies(uid)
			end
			uid
		end

		def self.user_never_exposed?(experiment_id)
			exposed_experiments.include?(experiment_id)
		end

		def self.tuid_cookie
			Lacmus.client_storage.temp_user_id_cookie
		end

		def self.exposed_experiments
			return [] unless Lacmus.client_storage.experiment_cookie
			Lacmus.client_storage.experiment_cookie.split(";")
		end

		# we add 1 to the concurrent tests requested to run from the admin
		# to include the control group
		def self.get_experiment_for_user_id
			current_temp_user_id % (experiment_slots_count + AMOUNT_OF_CONTROL_GROUPS)
		end

		def self.track_exposure(experiment_id)
			group = get_experiment_for_user_id
			return if group
			Lacmus.fast_storage.incr view_counter_key(experiment_id, group)
			Lacmus.client_storage.store_exposed_experiment(experiment_id)
		end

		def self.exposed_counter(experiment_id)
			Lacmus.fast_storage.incr view_counter_key(experiment_id, group)
		end

		# TODO: store in web_admin_prefs['experiment_slots_count'] and use it instead
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

		def self.view_counter_key(experiment_id, group)
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-counter-#{experiment_id.to_s}-#{group.to_s}"
		end

		def self.web_admin_prefs_key
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-web-admin-prefs"
		end

	end
end