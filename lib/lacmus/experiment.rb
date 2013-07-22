require_relative 'settings'
require_relative 'fast_storage'

module Lacmus
	class Experiment

		# Accessors
		attr_accessor :screenshot_url
		attr_accessor :errors

		attr_reader :id
		attr_reader :name
		attr_reader :description
		attr_reader :control_kpis
		attr_reader :experiment_kpis
		attr_reader :control_analytics
		attr_reader :experiment_analytics

		# Class variables
		# TODO: move to settings
		# @@web_admin_prefs = {}
		# @@web_prefs_last_loaded_at = nil

		def initialize(id)
			experiment = Lacmus::SlotMachine.find_experiment(id)

			@id 									= id
			@name 								= experiment[:name]
			@description 					= experiment[:description]
			@control_kpis 				= load_experiment_kpis(true)
			@experiment_kpis 			= load_experiment_kpis
			@control_analytics 		= load_experiment_analytics(true)
			@experiment_analytics = load_experiment_analytics
		end
	
		def available_kpis
			@control_kpis.merge(@experiment_kpis).keys
		end

		def control_kpis(kpi)
			@control_kpis[kpi.to_s].to_i
		end

		def experiment_kpis(kpi)
			@experiment_kpis[kpi.to_s].to_i
		end

		def load_experiment_kpis(is_control = false)
			kpis_hash = {}
			kpis = Lacmus.fast_storage.zrange(self.class.kpi_key(@id, is_control), 0, -1, :with_scores => true)
			kpis.each do |kpi_array|
				kpis_hash[kpi_array[0]] = kpi_array[1]
			end
			kpis_hash
		end

		def load_experiment_analytics(is_control = false)
			{exposures: (Lacmus.fast_storage.get self.class.exposure_key(@id, is_control))}
		end

		def safe_name(include_id = false)
			safe_name = name.gsub(' ', '_').downcase
			if include_id
				safe_name += "_#{id}"
			end
			safe_name
		end

		def reset
			self.class.reset_experiment(@id)
		end

		def self.reset_experiment(experiment_id)
			Lacmus.fast_storage.multi do
				Lacmus.fast_storage.del kpi_key(experiment_id)
				Lacmus.fast_storage.del kpi_key(experiment_id, true)
				Lacmus.fast_storage.del exposure_key(experiment_id)
				Lacmus.fast_storage.del exposure_key(experiment_id, true)
			end			
		end

		def self.mark_kpi!(kpi, experiment_id)
			if is_control_group?(experiment_id)
				Lacmus::SlotMachine.experiment_slots_without_control_group.each do |slot|
					Lacmus.fast_storage.zincrby kpi_key(slot, true), 1, kpi.to_s
				end
			else
				Lacmus.fast_storage.zincrby kpi_key(experiment_id), 1, kpi.to_s
			end
		end

		def self.track_experiment_exposure(experiment_id)
			if is_control_group?(experiment_id)
				Lacmus::SlotMachine.experiment_slots_without_control_group.each do |slot|
					Lacmus.fast_storage.incr exposure_key(experiment_id, true)
				end
			else
				Lacmus.fast_storage.incr exposure_key(experiment_id)
			end
		end

		private

		# def self.web_admin_prefs
		# 	if @@web_prefs_last_loaded_at.nil? || @@web_prefs_last_loaded_at < (Time.now - 60)
		# 		load_web_admin_prefs
		# 	end

		# 	@@web_admin_prefs
		# end

		def self.is_control_group?(experiment_id)
			experiment_id == 0
		end

		# TODO: remove me
		# returns the temp user id from the cookies if present. If not,
		# it generates a new one and creates a cookie for it
		# def self.current_temp_user_id
		# 	uid = tuid_cookie.value.to_i
		# 	if uid.zero?
		# 		uid = Lacmus::Utils.generate_tmp_user_id
		# 		Lacmus::ClientStorage.build_tuid_cookie(uid)
		# 	end
		# 	uid
		# end

		# TODO: remove me
		# def self.user_exposed_to_experiment?(experiment_id)
		# 	exposed_experiments.include?(experiment_id)
		# end

		# TODO: remove me
		# def self.exposed_experiments
		# 	return [] unless Lacmus::Lab.experiment_cookie
		# 	Lacmus::Lab.experiment_cookie
		# end

		# TODO: remove me
		# def self.track_control_group_exposure
		# 	track_experiment_exposure(0)
		# end

		# TODO: remove me
		# def self.exposed_counter(experiment_id)
		# 	Lacmus.fast_storage.incr view_counter_key(experiment_id, group)
		# end

		# TODO: remove me
		# def self.experiment_slots_count
		# 	Lacmus::SlotMachine.experiment_slots.count
		# end

		# TODO: move to settings
		# def self.load_web_admin_prefs
		# 	@@web_prefs_last_loaded_at = Time.now
		# 	@@web_admin_prefs = Marshal.load(Lacmus.fast_storage.get web_admin_prefs_key)
		# end

		# ------------------------------------------------
	
		def self.kpi_key(experiment_id, is_control = false)
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-#{is_control}-kpis-#{experiment_id.to_s}"
		end

		def self.exposure_key(experiment_id, is_control = false)
			"#{Lacmus::Settings::LACMUS_NAMESPACE}-#{is_control}-counter-#{experiment_id.to_s}"
		end

		# TODO: move to settings
		# def self.web_admin_prefs_key
		# 	"#{Lacmus::Settings::LACMUS_NAMESPACE}-web-admin-prefs"
		# end

	end

	class ExperimentHistoryItem < Experiment
		attr_accessor :user_tmp_id
		attr_accessor :exposed_at

		def initialize(user_tmp_id, experiment_id, exposed_at)
			@user_tmp_id = user_tmp_id
			@exposed_at  = exposed_at
			super(experiment_id)
		end

	end
end