module Lacmus
	class ExperimentSlice
		attr_accessor :name
		attr_accessor :description
		attr_accessor :screenshot_url
		attr_accessor :errors

		def initialize
			@errors = Array.new
		end

	end

end