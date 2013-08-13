require 'spec_helper'
require 'lacmus'

describe Lacmus::Experiment, "Experiment" do

  before(:each) do
    Lacmus.restart_user_ids_counter
    Lacmus::Experiment.nuke_all_experiments
  end

  # it "should log experiment" do
  # 	tmp_user_id = rand(1000000)

  # 	experiment_id = create_and_activate_experiment
  # 	experiment_id2 = create_and_activate_experiment

  #   Lacmus::ExperimentHistory.log_experiment(tmp_user_id, experiment_id)
  #   exps = Lacmus::ExperimentHistory.experiments(tmp_user_id)
  #   # expect(Lacmus::ExperimentHistory.experiments(tmp_user_id))
  #   Lacmus::ExperimentHistory.log_experiment(tmp_user_id, experiment_id2)
  #   # p Lacmus::ExperimentHistory.experiments(tmp_user_id)

  #   # expect(Lacmus::Lab.user_belongs_to_control_group?).to be_false
  #   # expect(get_exposures_for_experiment(experiment_id, true)).to eq(0)
  #   # expect(get_exposures_for_experiment(experiment_id)).to eq(1)
  # end

end