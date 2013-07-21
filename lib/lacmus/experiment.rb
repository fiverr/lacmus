require_relative 'settings'
require_relative 'fast_storage'

module Lacmus

	class Experiment
		attr_accessor :screenshot_url
		attr_accessor :errors

		# Class variables
		@@web_admin_prefs = {}
		@@web_prefs_last_loaded_at = nil

		def initialize(id)
			experiment = Lacmus::SlotMachine.find_experiment(id)

			@id = id
			@name = experiment[:name]
			@description = experiment[:description]
			@control_kpis = {}
			@experiment_kpis = load_experiment_kpis
			@control_analytics = {}
			@experiment_analytics = {}
		end

		def all_kpis
			{control: @control_kpis, experiment: @experiment_kpis}
		end

		def control_kpi(kpi)
			@control_kpis[kpi.to_s].to_i
		end

		def experiment_kpi(kpi)
			@experiment_kpis[kpi.to_s].to_i
		end

		# def self.expose_experiment(experiment_id)
		# 	return unless experiment_active?(experiment_id)

		# 	if user_exposed_to_experiment?(experiment_id)
		# 		track_exposure(experiment_id)
		# 	end
		# end

		# def self.active_experiments
		# 	Lacmus.fast_storage.smembers active_experiments_key
		# end

		def self.mark_kpi!(kpi, experiment_id)
			if is_control_group?(experiment_id)
				Lacmus::SlotMachine.experiment_slots_without_control_group.each do |slot|
					Lacmus.fast_storage.zincrby kpi_key(slot, true), 1, kpi.to_s
				end
			else
				Lacmus.fast_storage.zincrby kpi_key(experiment_id), 1, kpi.to_s
			end
		end

		def self.reset_all(experiment_id)
			Lacmus.fast_storage.multi do
				Lacmus.fast_storage.del kpi_key(experiment_id)
				Lacmus.fast_storage.del kpi_key(experiment_id, true)
			end
		end

		def load_experiment_kpis(control = false)
			kpis_hash = {}
			all_kpis_for_experiment(@id, control).each do |kpi_array|
				kpis_hash[kpi_array[0]] = kpi_array[1]
			end
			kpis_hash
		end

		def self.all_kpis_for_experiment(experiment_id, control)
			Lacmus.fast_storage.zrange(kpi_key(experiment_id, control), 0, -1, :with_scores => true)
		end

		private

		def self.web_admin_prefs
			if @@web_prefs_last_loaded_at.nil? || @@web_prefs_last_loaded_at < (Time.now - 60)
				load_web_admin_prefs
			end

			@@web_admin_prefs
		end

		def self.is_control_group?(experiment_id)
			experiment_id == 0
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

		def self.user_exposed_to_experiment?(experiment_id)
			exposed_experiments.include?(experiment_id)
		end

		# def self.exposed_experiments
		# 	return [] unless Lacmus::Lab.experiment_cookie
		# 	Lacmus::Lab.experiment_cookie
		# end

		# def self.track_control_group_exposure
		# 	track_experiment_exposure(0)
		# end

		def self.track_experiment_exposure(experiment_id)
			if is_control_group?(experiment_id)
				Lacmus::SlotMachine.experiment_slots_without_control_group.each do |slot|
					Lacmus.fast_storage.incr exposure_counter_key(experiment_id, true)
				end
			else
				Lacmus.fast_storage.incr exposure_counter_key(experiment_id)
			end
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
	
		def self.kpi_key(experiment_id, is_control = false)
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-#{is_control}-kpis-#{experiment_id.to_s}"
		end

		def self.exposure_counter_key(experiment_id, is_control = false)
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-#{is_control}-counter-#{experiment_id.to_s}"
		end

		def self.web_admin_prefs_key
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-web-admin-prefs"
		end

	end
end