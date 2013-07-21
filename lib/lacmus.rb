# require "lacmus/version"
require 'lacmus/settings'
require 'lacmus/fast_storage'
require 'lacmus/utils'
require 'lacmus/lab'
require 'lacmus/experiment'
require 'lacmus/slot_machine'
require 'lacmus/helper'
require 'lacmus/experiment_slice'
require 'lacmus/kpi_manager'

module Lacmus

	@@fast_engine = nil
	@@client_engine = nil

	def self.fast_storage
		@@fast_engine ||= Lacmus::FastStorage.instance
	end

end
