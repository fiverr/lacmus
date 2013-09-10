module Lacmus
	module AsyncLab
		extend self
		extend Lab

		class NotImplemented < StandardError; end

		attr_accessor :__lcm__cached_user_id

		def mark_kpi!(kpi, alternative_user_id)
			user_id = AlternativeUser.get_user_id(alternative_user_id)
			unless user_id
				lacmus_logger "Can't mark async kpi: #{kpi} because lacmus id" <<
										  "wasn't found for #{alternative_user_id}" and return
			end

			self.__lcm__cached_user_id = user_id.to_i
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