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

  it "should not track user exposed to completed exeriment" do
  	# p helper.request.cookies[:awesome]
  	# Lacmus::Experiment.tuid_cookie
  end

  it "should not track exposed user twice" do
  end

end