module Lacmus
	module Settings

		# Global Variables
		# TODO: Make this code decent and readable.
		$__lacmus_has_rails = defined?(Rails.root)
		if $__lacmus_has_rails
			ROOT = $__lacmus_has_rails && Rails.root ? Rails.root : Dir.pwd
			ENV = Rails.env	
		else
			ROOT = ENV == "test" ? "#{Dir.pwd}/spec" : "#{Dir.pwd}/spec"
			ENV = "test"
		end

		# Constants
		LACMUS_NAMESPACE = "lcms-#{ENV}"

		puts "------> Lacmus initiated, ROOT: #{ROOT},  ENV = #{ENV}"
	end
end