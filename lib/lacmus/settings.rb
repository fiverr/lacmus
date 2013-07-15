module Lacmus
	module Settings
		LACMUS_NAMESPACE = "lcms"
		$has_rails = defined?(Rails.root)
		if $has_rails
			ROOT = Rails.root
			ENV = Rails.env
		else
			ROOT = "#{Dir.pwd}/spec"
			ENV = "test"
		end

	end
end