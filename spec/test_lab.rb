require 'lacmus'

describe Lacmus::Lab, "Lab" do

	before(:all) do
    @experiment_name = "experimentum"
    @experiment_description = "dekaprius dela karma"
      Lacmus::Lab.send :define_method, :cookies do
        {}
      end
  end

  def self.cookies
    @cookies ||= {}
  end
  
  before(:each) do
    Lacmus::SlotMachine.nuke_all_experiments
  end

  it "show render a changing group each time" do
    binding.pry
    experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
    Lacmus::SlotMachine.activate_experiment(experiment_id)
    result = Lacmus::Lab.simple_experiment(experiment_id, "group_a", "experiment_group")
  end

  it "should not track user exposed to completed exeriment" do
  end

  it "should not track exposed user twice" do
  end

end