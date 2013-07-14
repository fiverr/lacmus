module Lacmus
	module Settings
		LACMUS_NAMESPACE = "lcms"
		ROOT = (defined?(Rails.root) && Rails.root) ? Rails.root : Dir.pwd
		ENV = Rails.env
	end
end