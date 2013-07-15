require 'lacmus'
# https://github.com/rspec/rspec-expectations

describe Lacmus::SlotMachine, "Management Features" do

  before(:all) do
    @experiment_name = "experimentum"
    @experiment_description = "dekaprius dela karma"
  end
  
  before(:each) do
    Lacmus::SlotMachine.nuke_all_experiments
  end

	it "creates experiments as pending" do 
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
		experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
		move_result = Lacmus::SlotMachine.move_experiment(experiment_id, :pending, :active)
		expect(move_result).to be_true

		move_result = Lacmus::SlotMachine.move_experiment(experiment_id, :active, :pending)
		experiment_pending = Lacmus::SlotMachine.get_experiment_from(:pending, experiment_id)
		experiment_active = Lacmus::SlotMachine.get_experiment_from(:active, experiment_id)		

		expect(experiment_pending[:name]).to eq(@experiment_name)
		expect(experiment_active).to eq({})
	end

end