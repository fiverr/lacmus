module Lacmus
	module Settings

		# Global Variables
		# TODO: Ugly and shitty code, refactor to make it something decent
		$has_rails = defined?(Rails.root)
		if $has_rails
			ROOT = $has_rails && Rails.root ? Rails.root : Dir.pwd
			ENV = Rails.env	
		else
			ROOT = ENV == "test" ? "#{Dir.pwd}/spec" : "#{Dir.pwd}/spec"
			ENV = "test"
		end

		# Constants
		LACMUS_NAMESPACE = "lcms#{ENV}"

		puts "------> RAILS ROOT IS: #{ROOT} | ENV = #{ENV}"

	end
end