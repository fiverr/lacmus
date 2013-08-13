require 'spec_helper'
require 'lacmus'

describe Lacmus::SlotMachine, "Management Features" do

	SLOT_MACHINE_STARTING_STATE = [0,-1]

  before(:each) do
    Lacmus::Experiment.nuke_all_experiments
    Lacmus::SlotMachine.reset_slots_to_defaults
    Lacmus::SlotMachine.reset_worker_cache
  end

	describe "Basic functionality" do

		it "slot machine should start empty with expected number of slots" do 
			expect(Lacmus::SlotMachine.experiment_slot_ids).to eq(SLOT_MACHINE_STARTING_STATE)
		end

		it "place experiment in slot should fill the slots with experiments" do 
			experiment_id = create_and_activate_experiment.id
			expect(Lacmus::SlotMachine.experiment_slot_ids).not_to eq(SLOT_MACHINE_STARTING_STATE)
			expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id])
		end

		it "should not override slot when taken" do
			experiment_id1 = create_and_activate_experiment.id
			experiment_id2 = create_and_activate_experiment.id

			expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1])
		end

		it "should remove  an experiment from slot" do 
			experiment_id1 = create_and_activate_experiment.id
			expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1])

			Lacmus::SlotMachine.remove_experiment_from_slot(experiment_id1)
			expect(Lacmus::SlotMachine.experiment_slot_ids).to eq(SLOT_MACHINE_STARTING_STATE)
		end

	end # of describe "Basic functionality"

	describe "Resize functionality" do

		it "should resize a slot array" do
			slots_original = Lacmus::SlotMachine.experiment_slots
			Lacmus::SlotMachine.resize_and_reset_slot_array(slots_original.count + 1)
			Lacmus::SlotMachine.reset_worker_cache
			sleep 1
			slots_resized = Lacmus::SlotMachine.experiment_slots
			expect(slots_original.count).to be < slots_resized.count
		end

		it "should allow resizing of slot the array, leaving the exising items intact" do 
			experiment_id1 = create_and_activate_experiment.id
			expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1])

			Lacmus::SlotMachine.resize_and_reset_slot_array(5)
			Lacmus::SlotMachine.reset_worker_cache
			expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1, -1, -1, -1])

			experiment_id2 = create_and_activate_experiment.id
			expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1, experiment_id2, -1, -1])
		end

		it "should update the experiment start time after resize" do
			experiment_id1 = create_and_activate_experiment.id
			start_time = Lacmus::SlotMachine.last_experiment_reset(experiment_id1)
			expect(start_time).to be > 0

			sleep 1
			Lacmus::SlotMachine.resize_and_reset_slot_array(3)
			Lacmus::SlotMachine.reset_worker_cache

			start_time2 = Lacmus::SlotMachine.last_experiment_reset(experiment_id1)
			expect(start_time2).to be > 0
			expect(start_time2).not_to eq(start_time)
		end

	end # of describe "Resize functionality"

	describe "Restart functionality" do

		it "clearing the slot machine should bring it back to defaults" do 
			experiment_id1 = create_and_activate_experiment.id
			expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1])

			Lacmus::SlotMachine.clear_experiment_slot_ids
			Lacmus::SlotMachine.reset_worker_cache
			expect(Lacmus::SlotMachine.experiment_slot_ids).to eq(SLOT_MACHINE_STARTING_STATE)

			Lacmus::SlotMachine.resize_and_reset_slot_array(5)
			Lacmus::SlotMachine.reset_worker_cache
			Lacmus::SlotMachine.clear_experiment_slot_ids
			expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, -1, -1, -1, -1])
		end

		it "should check that resetting an experiment changes its start, and does not affect other experiments" do
			Lacmus::SlotMachine.resize_and_reset_slot_array(3)
			Lacmus::SlotMachine.reset_worker_cache
			experiment_id1 = create_and_activate_experiment.id
			experiment_id2 = create_and_activate_experiment.id
			creation_time1 = Time.at(Lacmus::SlotMachine.experiment_slots[1][:start_time_as_int].to_i)
			creation_time2 = Time.at(Lacmus::SlotMachine.experiment_slots[2][:start_time_as_int].to_i)
			expect(creation_time1).to be > (Time.now - 10)
			expect(creation_time2).to be > (Time.now - 10)
			expect(creation_time1).to be < (Time.now + 10)
			expect(creation_time2).to be < (Time.now + 10)

			sleep 1
			experiment_id1_obj = Lacmus::Experiment.find_in_list(experiment_id1, :active)
			experiment_id1_obj.restart!

			update_time1 = Time.at(Lacmus::SlotMachine.experiment_slots[1][:start_time_as_int].to_i)
			update_time2 = Time.at(Lacmus::SlotMachine.experiment_slots[2][:start_time_as_int].to_i)
			expect(update_time1).to be > creation_time1
			expect(update_time2).to eq(creation_time2)
		end

	end # of describe "Restart functionality"

	describe "Available slots functionality" do

		it "slot machine should return the first available slot, even if in the middle of the stack" do 
			Lacmus::SlotMachine.resize_and_reset_slot_array(5)
			Lacmus::SlotMachine.reset_worker_cache
			experiment_id1 = create_and_activate_experiment.id
			experiment_id2 = create_and_activate_experiment.id
			experiment_id3 = create_and_activate_experiment.id

			Lacmus::SlotMachine.remove_experiment_from_slot(experiment_id2)
			expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1, -1, experiment_id3, -1])
			experiment_id4 = create_and_activate_experiment.id
			expect(Lacmus::SlotMachine.experiment_slot_ids).to eq([0, experiment_id1, experiment_id4, experiment_id3, -1])
		end

		it "full slot machine should not return an available slot" do 		
			experiment_id1 = create_and_activate_experiment.id
			expect(Lacmus::SlotMachine.find_available_slot).to be_nil
		end

	end # of describe "Available slots functionality"

end # of describe Lacmus::SlotMachine, "Management Features"