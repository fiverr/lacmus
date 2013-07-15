module Lacmus
	module Helper
		def moshe
			puts "moshe is here"
		end
	end
end

ActionController::Base.send(:include, Lacmus::Helper)