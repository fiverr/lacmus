# @todo suppoert mutually exclusive experiments
#
module TrafficAllocator
	extend self

	# @todo implement me
	#
	def experiment_exposure(experiment_id)
		30
	end

	# @todo implement me
	# hash 			 = {'a' => 40, 'b' => 30, 'c' => 30}
	#
	def variations_allocation(experiment_id)
		allocation_array = []
		variations_hash  = {'a' => 50, 'b' => 50}
		variations_hash.each {|k,v| v.times {allocation_array.push(k)}}
		allocation_array
	end

end