# require "lacmus/version"
require 'lacmus/fast_storage'
require 'lacmus/utils'
require 'lacmus/experiment'
require 'lacmus/slot_machine'
# require 'lacmus/helper'

module Lacmus

	@@fast_engine = nil
	@@client_engine = nil

	def self.fast_storage
		@@fast_engine ||= Lacmus::FastStorage.instance
	end

	def self.client_storage
		@@client_engine ||= Lacmus.client_storage
	end

end
