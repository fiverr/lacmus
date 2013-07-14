module Lacmus
	module ClientStorage

		def self.build_tuid_cookies(temp_user_id)
			temp_user_id_cookie = {:value => "#{temp_user_id}", :expires => max_cookie_time}
		end

		def self.store_exposed_experiment(experiment_id)
			if experiment_cookie.nil?
				exposed_experiments_str = ''
			else
				exposed_experiments_str = experiment_cookie.value.to_s
			end
			experiment_cookie = {:value => "#{exposed_experiments_str};#{experiment_id.to_s}", :expires => max_cookie_time}
		end


		def self.temp_user_id_cookie
			cookies['lacmus_tuid']
		end

		def self.experiment_cookie
			cookies['lacmus_exps']
		end

		private

		def max_cookie_time
			Time.now.utc.to_i + (60 * 60 * 24 * 365)
		end

	end
end
