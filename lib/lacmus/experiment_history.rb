require 'redis'

require 'lacmus'
require 'lacmus/experiment'

module Lacmus
	# Responsible to store all the experiments that any user
	# was exposed to. Can be used to run all sort of BI/analytics.
	module ExperimentHistory
		extend self

		# Set the user's cookies to expire after 1 month.
		KEY_EXPIRE_IN_SECONDS = 2592000

		# Adds the given experiment_id to the experiment history
		# of the given user_id.
		#
		# @param [ Integer ] user_id
		# @param [ Integer ] experiment_id
		# @param [ Boolean ] is_control Whether the user belongs to control group or
		# 	to the experiment. Defaults to false.
		#
		def add(user_id, experiment_id, is_control = false)
			Lacmus.fast_storage.multi do
				Lacmus.fast_storage.zadd key(user_id, is_control), Time.now.utc.to_i, experiment_id
				Lacmus.fast_storage.expire key(user_id, is_control), KEY_EXPIRE_IN_SECONDS
			end
		end

		# Returns the entire experiment history for the given
		# user_id, both as control group and as experiment group.
		#
		# @param [ Integer ] user_id
		#
		# @example User id = 34000 was exposed to experiment_id = 45 as control group
		# 	Lacmus::ExperimentHistory.all(34000) # =>
		# 	[#<Lacmus::ExperimentHistoryItem:0x007ff9ac2efb28 @user_id=1600, @exposed_at=2013-08-14 17:37:59 +0300, @experiment_id=9495, @control=true,
		# 		@experiment=#<Lacmus::Experiment:0x007ff9ac2f4628 @id=9495, @status=:pending, @name="experimentum", @description="dekaprius dela karma",
		# 			@screenshot_url="http://google.com",
		# 			@start_time=nil, @end_time=nil, @control_kpis={}, @experiment_kpis={}, @control_analytics={"exposures"=>nil},
		# 			@experiment_analytics={"exposures"=>nil}, @errors=[]>>]
		#
		# @return [ Array<ExperimentHistoryItem> ] Array of ExperimentHistoryItem objects
		#
		def all(user_id)
			control_group 	 = for_group(user_id, true)
			experiment_group = for_group(user_id, false)

			control_group + experiment_group
		end

		# Returns experiment history for the given user_id and group.
		#
		# @param [ Integer ] user_id The user_id
		# @param [ Boolean ] is_control True for experiment history as control group,
		# 	false for experiment history as experiment group user.
		#
		# @return [ Array<ExperimentHistoryItem> ] Array of ExperimentHistoryItem objects
		#
		def for_group(user_id, is_control)
			history = []
			data = Lacmus.fast_storage.zrange(key(user_id, is_control), 0, -1, :with_scores => true)
			data.each do |item|
				experiment_id, exposed_at = item[0], item[1]
				history << ExperimentHistoryItem.new(user_id, experiment_id, exposed_at, is_control)
			end
			history
		end

		# Clear the entire experiment history for the given user_id, both
		# as control group and as experiment group.
		#
		def clear(user_id)
			Lacmus.fast_storage.del key(user_id)
			Lacmus.fast_storage.del key(user_id, true)
		end

		# Return the redis key for the given user_id and group.
		#
		# @param [ Integer ] user_id The user_id
		# @param [ Boolean ] is_control True to get the key for control group,
		# 	false for experiment group.
		#
		# @return [ String ]
		#
		def key(user_id, is_control = false)
			"#{LACMUS_PREFIX}-exp-history-#{user_id}-#{is_control}"
		end

	end # of ExperimentHistory
end # of Lacmus