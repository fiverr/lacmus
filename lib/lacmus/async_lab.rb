module Lacmus
	module AsyncLab
		extend Lab
		extend self

		class NotImplemented < StandardError; end #:nodoc:

		attr_accessor :__lcm__cached_user_id

		def mark_kpi!(kpi, alternative_user_id)
			user_id = AlternativeUser.get_user_id(alternative_user_id)
			self.__lcm__cached_user_id = user_id
			super(kpi)
		end

		def render_control_version
			raise NotImplemented
		end

		def render_experiment_version
			raise NotImplemented
		end

		def simple_experiment
			raise NotImplemented
		end

	end
end