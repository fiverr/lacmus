module Lacmus
	class Railtie < Rails::Railtie

		config.after_initialize do
			Lacmus.fast_storage.client.reconnect if defined?(Lacmus.fast_storage)
		end

		ActionController::Base.send(:include, Lacmus::Lab)

	end
end