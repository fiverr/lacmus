module Lacmus
	class Railtie < Rails::Railtie

		initializer 'lacmus_railtie.configure_rails_initialization' do
			Lacmus.reset_fast_storage
		end

		ActionController::Base.send(:include, Lacmus::Lab)

	end
end