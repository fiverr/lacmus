require 'spec_helper'
require 'lacmus'

describe Lacmus::Experiment, "Experiment" do

  before(:each) do
    Lacmus.restart_user_ids_counter
    Lacmus::Experiment.nuke_all_experiments
  end

  describe "Basic slots functionality" do

  	it "should log experiment for control user" do
	  	user_id 			= rand(10000)
	  	experiment_id = rand(100)
	  	Lacmus::ExperimentHistory.clear(user_id)

	    Lacmus::ExperimentHistory.add(user_id, experiment_id, true)
	    control_group 		= Lacmus::ExperimentHistory.for_group(user_id, true)
	    experiments_group = Lacmus::ExperimentHistory.for_group(user_id, false)
	    expect(control_group).not_to be_empty
	    expect(experiments_group).to be_empty

	    logged_experiment = control_group.first
	    first_exp_id 		  = logged_experiment.instance_variable_get("@experiment_id")
	    is_contol 			  = logged_experiment.instance_variable_get("@control")

	    expect(first_exp_id).to eq(experiment_id)
	    expect(is_contol).to be_true
	  end

	  it "should log experiment for experiment user" do
	  	user_id 			= rand(10000)
	  	experiment_id = rand(100)
	  	Lacmus::ExperimentHistory.clear(user_id)

	    Lacmus::ExperimentHistory.add(user_id, experiment_id, false)
	    control_group 		= Lacmus::ExperimentHistory.for_group(user_id, true)
	    experiments_group = Lacmus::ExperimentHistory.for_group(user_id, false)
	    expect(control_group).to be_empty
	    expect(experiments_group).not_to be_empty

	    logged_experiment = experiments_group.first
	    first_exp_id 		  = logged_experiment.instance_variable_get("@experiment_id")
	    is_contol 			  = logged_experiment.instance_variable_get("@control")

	    expect(first_exp_id).to eq(experiment_id)
	    expect(is_contol).to be_false
	  end

  end # of describe "Basic slots functionality"

end