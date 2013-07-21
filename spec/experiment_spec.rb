require 'lacmus'

describe Lacmus::Experiment, "Experiment" do

	before(:all) do
    @experiment_name = "experimentum"
    @experiment_description = "dekaprius dela karma"
  end
  
  before(:each) do
    Lacmus::SlotMachine.nuke_all_experiments
  end

  it "should track user exposed to active exeriment" do
  end

  it "should increment kpi value when marking kpi" do
    # experiment_id = create_and_activate_experiment
    # p experiment_id
    # p Lacmus::Experiment.key(experiment_id)
    # p Lacmus::Experiment.all_kpis_for_experiment(experiment_id)
    # p Lacmus::Experiment.all_keys_as_hash(experiment_id)
    # Lacmus::Experiment.mark_kpi!('ftb', experiment_id)
    # Lacmus::Experiment.mark_kpi!('ftg', experiment_id)
    # p Lacmus::Experiment.all_keys_as_hash(experiment_id)
    # p Lacmus::Experiment.all_kpis_for_experiment(experiment_id)
  end

  it "should not track user exposed to completed exeriment" do
  	# p helper.request.cookies[:awesome]
  	# Lacmus::Experiment.tuid_cookie
  end

  it "should not track exposed user twice" do
  end

end