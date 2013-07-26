require 'lacmus'
# https://github.com/rspec/rspec-expectations


describe Lacmus::SlotMachine, "Management Features" do

	SLOT_MACHINE_STARTING_STATE = [0,-1]

  before(:all) do
    @experiment_name = "experimentum"
    @experiment_description = "dekaprius dela karma"
  end
  
  before(:each) do
    Lacmus::SlotMachine.nuke_all_experiments
    Lacmus::SlotMachine.reset_slots_to_defaults
    reset_active_experiments_cache
  end

  def create_and_activate_experiment
		experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
		move_result = Lacmus::SlotMachine.move_experiment(experiment_id, :pending, :active)
		experiment_id
  end

  def reset_active_experiments_cache
		$__lcms__loaded_at_as_int = 0
	end

	it "should create experiments as pending" do 
		experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
		expect(experiment_id).to be > 0
		experiment_in_pending_queue = Lacmus::SlotMachine.get_experiment_from(:pending, experiment_id)
		expect(experiment_in_pending_queue[:name]).to eq(@experiment_name)
		expect(experiment_in_pending_queue[:description]).to eq(@experiment_description)
		expect(experiment_in_pending_queue[:experiment_id]).to eq(experiment_id)
	end

	it "should remove experiment from list" do 
		experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
		Lacmus::SlotMachine.remove_experiment_from(:pending, experiment_id)
		experiment = Lacmus::SlotMachine.get_experiment_from(:pending, experiment_id)
		expect(experiment).to be_empty
	end

	it "should move experiment from pending to active" do 
		experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
		move_result = Lacmus::SlotMachine.move_experiment(experiment_id, :pending, :active)
		expect(move_result).to be_true

		experiment_pending = Lacmus::SlotMachine.get_experiment_from(:pending, experiment_id)
		experiment_active = Lacmus::SlotMachine.get_experiment_from(:active, experiment_id)		

		expect(experiment_pending).to eq({})
		expect(experiment_active[:name]).to eq(@experiment_name)
		expect(Lacmus::SlotMachine.experiment_slot_ids[1]).not_to be_nil
	end

	it "should move experiment from active to pending" do 
		experiment_id = create_and_activate_experiment

		Lacmus::SlotMachine.move_experiment(experiment_id, :active, :pending)
		experiment_pending = Lacmus::SlotMachine.get_experiment_from(:pending, experiment_id)
		experiment_active = Lacmus::SlotMachine.get_experiment_from(:active, experiment_id)		

		expect(experiment_pending[:name]).to eq(@experiment_name)
		expect(experiment_active).to eq({})
	end


	# ----------------------------------------------------------------
	#                BASIC SLOT MACHINE FUNCTIONALITY
	# ----------------------------------------------------------------

	it "slot machine should start empty with expected number of slots" do 
		# $__lcms__loaded_at_as_int   = 0
		# $__lcms__active_experiments = nil
		expect(Lacmus::SlotMachine.experiment_slot_ids).to eq(SLOT_MACHINE_STARTING_STATE)
	end

	it "place experiment in slot should fill the slots with experiments" do 
		experiment_id = create_and_activate_experiment
		expect(Lacmus::SlotMachine.experiment_slot_ids).not_to eq(SLOT_MACHINE_STARTING_STATE)
		expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id])
	end

	it "should not override slot when taken" do
		experiment_id1 = create_and_activate_experiment
		experiment_id2 = create_and_activate_experiment

		expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1])
	end

	it "should destroy experiments if needed" do
		Lacmus::SlotMachine.resize_slot_array(3)
		reset_active_experiments_cache
		experiment_id1 = create_and_activate_experiment
		experiment_id2 = create_and_activate_experiment

		expect(Lacmus::SlotMachine.experiment_slot_ids[1]).to eq(experiment_id1)
		Lacmus::SlotMachine.destroy_experiment(:active, experiment_id1)

		reset_active_experiments_cache
		expect(Lacmus::SlotMachine.experiment_slot_ids[1]).to eq(-1)
		expect(Lacmus::SlotMachine.get_experiment_from(:active, experiment_id1)).to eq({})

		expect(Lacmus::SlotMachine.get_experiment_from(:active, experiment_id2)).not_to eq({})
	end

	it "removing an experiment from slots should work well" do 
		experiment_id1 = create_and_activate_experiment
		expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1])

		Lacmus::SlotMachine.remove_experiment_from_slot(experiment_id1)
		expect(Lacmus::SlotMachine.experiment_slot_ids).to eq(SLOT_MACHINE_STARTING_STATE)
	end

	it "should resize a slot array" do
		Lacmus::SlotMachine.worker_cache_interval = 0
		slots_original = Lacmus::SlotMachine.experiment_slots
		Lacmus::SlotMachine.resize_slot_array(slots_original.count + 1)
		sleep 1
		slots_resized = Lacmus::SlotMachine.experiment_slots
		expect(slots_original.count).to be < slots_resized.count
	end

	it "should allow resizing of slot the array, leaving the exising items intact" do 
		experiment_id1 = create_and_activate_experiment
		expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1])

		Lacmus::SlotMachine.resize_slot_array(5)
		reset_active_experiments_cache
		expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1, -1, -1, -1])

		experiment_id2 = create_and_activate_experiment
		expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1, experiment_id2, -1, -1])
	end

	it "clearing the slot machine should bring it back to defaults" do 
		experiment_id1 = create_and_activate_experiment
		expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1])

		Lacmus::SlotMachine.clear_experiment_slot_ids
		reset_active_experiments_cache
		expect(Lacmus::SlotMachine.experiment_slot_ids).to eq(SLOT_MACHINE_STARTING_STATE)

		Lacmus::SlotMachine.resize_slot_array(5)
		reset_active_experiments_cache
		Lacmus::SlotMachine.clear_experiment_slot_ids
		expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, -1, -1, -1, -1])
	end

	it "slot machine should return the first available slot, even if in the middle of the stack" do 
		Lacmus::SlotMachine.resize_slot_array(5)
		reset_active_experiments_cache
		experiment_id1 = create_and_activate_experiment
		experiment_id2 = create_and_activate_experiment
		experiment_id3 = create_and_activate_experiment

		Lacmus::SlotMachine.remove_experiment_from_slot(experiment_id2)
		expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1, -1, experiment_id3, -1])
		experiment_id4 = create_and_activate_experiment
		expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1, experiment_id4, experiment_id3, -1])
	end

	it "full slot machine should not return an available slot" do 		
		experiment_id1 = create_and_activate_experiment
		expect(Lacmus::SlotMachine.find_available_slot).to be_nil
	end

	it "should check that resetting an experiment changes its start, and does not affect other experiments" do
		Lacmus::SlotMachine.worker_cache_active = false
		Lacmus::SlotMachine.resize_slot_array(3)
		experiment_id1 = create_and_activate_experiment
		experiment_id2 = create_and_activate_experiment
		creation_time1 = Time.at(Lacmus::SlotMachine.experiment_slots[1][:start_time_as_int].to_i)
		creation_time2 = Time.at(Lacmus::SlotMachine.experiment_slots[2][:start_time_as_int].to_i)
		expect(creation_time1).to be > (Time.now - 10)
		expect(creation_time2).to be > (Time.now - 10)
		expect(creation_time1).to be < (Time.now + 10)
		expect(creation_time2).to be < (Time.now + 10)
		# now we wait a second, and reset one experiment
		sleep 1
		Lacmus::SlotMachine.restart_experiment(experiment_id1)
		update_time1 = Time.at(Lacmus::SlotMachine.experiment_slots[1][:start_time_as_int].to_i)
		update_time2 = Time.at(Lacmus::SlotMachine.experiment_slots[2][:start_time_as_int].to_i)
		expect(update_time1).to be > creation_time1
		expect(update_time2).to eq(creation_time2)
	end

end