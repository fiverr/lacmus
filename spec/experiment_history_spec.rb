require 'spec_helper'
require 'lacmus'

describe Lacmus::Experiment, "Experiment" do

  before(:each) do
    Lacmus.restart_user_ids_counter
    Lacmus::Experiment.nuke_all_experiments
  end

  describe "Basic slots functionality" do

  	it "should log experiment" do
	  	user_id = rand(1000000)

	  	experiment_id = create_and_activate_experiment.id
	    Lacmus::ExperimentHistory.add(user_id, experiment_id)

	    exps = Lacmus::ExperimentHistory.experiments(user_id)
	    expect(exps).not_to be_empty

	    first_exp_id = exps.first.instance_variable_get("@experiment_id")
	    expect(first_exp_id).to eq(experiment_id)
	  end

  end # of describe "Basic slots functionality"

end