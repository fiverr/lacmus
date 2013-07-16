require 'lacmus'
# https://github.com/rspec/rspec-expectations


describe Lacmus::SlotMachine, "Management Features" do

	SLOT_MACHINE_STARTING_STATE = [0]

  before(:all) do
    @experiment_name = "experimentum"
    @experiment_description = "dekaprius dela karma"
  end
  
  before(:each) do
    Lacmus::SlotMachine.nuke_all_experiments
  end

  def create_and_activate_experiment
		experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
		move_result = Lacmus::SlotMachine.move_experiment(experiment_id, :pending, :active)
		experiment_id
  end

	it "should create experiments as pending" do 
		experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
		expect(experiment_id).to be > 0
		experiment_in_pending_queue = Lacmus::SlotMachine.get_experiment_from(:pending, experiment_id)
		expect(experiment_in_pending_queue[:name]).to eq(@experiment_name)
		expect(experiment_in_pending_queue[:description]).to eq(@experiment_description)
		expect(experiment_in_pending_queue[:experiment_id]).to eq(experiment_id)
	end

	it "removes an experiment from list" do 
		experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
		Lacmus::SlotMachine.remove_experiment_from(:pending, experiment_id)
		experiment = Lacmus::SlotMachine.get_experiment_from(:pending, experiment_id)
		expect(experiment).to be_empty
	end

	it "move an experiment from pending to active" do 
		experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
		move_result = Lacmus::SlotMachine.move_experiment(experiment_id, :pending, :active)
		expect(move_result).to be_true

		experiment_pending = Lacmus::SlotMachine.get_experiment_from(:pending, experiment_id)
		experiment_active = Lacmus::SlotMachine.get_experiment_from(:active, experiment_id)		

		expect(experiment_pending).to eq({})
		expect(experiment_active[:name]).to eq(@experiment_name)
		expect(Lacmus::SlotMachine.experiment_slots[0]).not_to be_nil
	end

	it "move an experiment from active to pending" do 
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
		expect(Lacmus::SlotMachine.experiment_slots).to eq(SLOT_MACHINE_STARTING_STATE)
	end

	it "place experiment in slot should fill the slots with experiments" do 
		experiment_id = create_and_activate_experiment
		expect(Lacmus::SlotMachine.experiment_slots).not_to eq(SLOT_MACHINE_STARTING_STATE)
		expect(Lacmus::SlotMachine.experiment_slots).to eq([experiment_id])
	end

	it "should not override slot when taken" do
		experiment_id1 = create_and_activate_experiment
		experiment_id2 = create_and_activate_experiment

		expect(Lacmus::SlotMachine.experiment_slots).to eq([experiment_id1])
	end

	it "removing an experiment from slots should work well" do 
		experiment_id1 = create_and_activate_experiment
		expect(Lacmus::SlotMachine.experiment_slots).to eq([experiment_id1])

		Lacmus::SlotMachine.remove_experiment_from_slot(experiment_id1)
		expect(Lacmus::SlotMachine.experiment_slots).to eq(SLOT_MACHINE_STARTING_STATE)
	end

	it "resizing slot array should work and leave the exising items intact" do 
		experiment_id1 = create_and_activate_experiment
		expect(Lacmus::SlotMachine.experiment_slots).to eq([experiment_id1])

		Lacmus::SlotMachine.resize_slot_array(5)
		expect(Lacmus::SlotMachine.experiment_slots).to eq([experiment_id1, 0, 0, 0, 0])

		experiment_id2 = create_and_activate_experiment
		expect(Lacmus::SlotMachine.experiment_slots).to eq([experiment_id1, experiment_id2, 0, 0, 0])
	end

	it "clearing the slot machine should bring it back to defaults" do 
		experiment_id1 = create_and_activate_experiment
		expect(Lacmus::SlotMachine.experiment_slots).to eq([experiment_id1])

		Lacmus::SlotMachine.clear_experiment_slots
		expect(Lacmus::SlotMachine.experiment_slots).to eq(SLOT_MACHINE_STARTING_STATE)

		Lacmus::SlotMachine.resize_slot_array(5)
		Lacmus::SlotMachine.clear_experiment_slots
		expect(Lacmus::SlotMachine.experiment_slots).to eq([0, 0, 0, 0, 0])
	end

	it "slot machine should return the first available slot, even if in the middle of the stack" do 
		Lacmus::SlotMachine.resize_slot_array(5)
		experiment_id1 = create_and_activate_experiment
		experiment_id2 = create_and_activate_experiment
		experiment_id3 = create_and_activate_experiment

		Lacmus::SlotMachine.remove_experiment_from_slot(experiment_id2)
		expect(Lacmus::SlotMachine.experiment_slots).to eq([experiment_id1, 0, experiment_id3, 0, 0])
		experiment_id4 = create_and_activate_experiment
		expect(Lacmus::SlotMachine.experiment_slots).to eq([experiment_id1, experiment_id4, experiment_id3, 0, 0])
	end

	it "full slot machine should not return an available slot" do 		
		experiment_id1 = create_and_activate_experiment
		expect(Lacmus::SlotMachine.find_available_slot).to be_nil
	end
end