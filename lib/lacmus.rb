# require "lacmus/version"
require 'lacmus/settings'
require 'lacmus/fast_storage'
require 'lacmus/utils'
require 'lacmus/lab'
require 'lacmus/experiment'
require 'lacmus/slot_machine'
require 'lacmus/experiment_history'

module Lacmus
	extend self

	# Constants
	LACMUS_NAMESPACE = "lcms-#{ENV}"

	# Global Variables
	$__lacmus_has_rails = defined?(Rails.root)
	
	if $__lacmus_has_rails
		ROOT = $__lacmus_has_rails && Rails.root ? Rails.root : Dir.pwd
		ENV = Rails.env	
	else
		ROOT = ENV == "test" ? "#{Dir.pwd}/spec" : "#{Dir.pwd}/spec"
		ENV = "test"
	end

	# Class Variables
	@@fast_engine = nil
	@@client_engine = nil

	def fast_storage
		@@fast_engine ||= Lacmus::FastStorage.instance
	end

	def namespace
		Lacmus::Settings::LACMUS_NAMESPACE
	end

end
