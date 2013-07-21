require 'lacmus'

describe Lacmus::KpiManager, "KpiManager" do

	# before(:all) do
 #    @experiment_name = "experimentum"
 #    @experiment_description = "dekaprius dela karma"
 #  end
  
  before(:each) do
    Lacmus::SlotMachine.nuke_all_experiments
  end

  def create_and_activate_experiment
    experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
    Lacmus::SlotMachine.activate_experiment(experiment_id)
    experiment_id
  end

  it "should increment kpi value when marking kpi" do
  	experiment_id = create_and_activate_experiment
  	p experiment_id
  	experiment_id = 5
  	p Lacmus::KpiManager.all_kpis_for_experiment(experiment_id)
  	Lacmus::KpiManager.mark('ftb', experiment_id)
  	Lacmus::KpiManager.mark('ftg', experiment_id)
  	p Lacmus::KpiManager.all_kpis_for_experiment(experiment_id)
  end

  it "should reset kpi values for experiment" do
	end

end