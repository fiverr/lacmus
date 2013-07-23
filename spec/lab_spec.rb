require 'lacmus'
include Lacmus::Lab
describe Lacmus::Lab, "Lab" do

	before(:all) do
  
    @experiment_name = "experimentum"
    @experiment_description = "dekaprius dela karma"

		Lacmus::Lab.instance_eval do
			@cookies = {}

    	def self.[](index)
			  @cookies[index]
			end

			def self.[]=(index,value)
			  @cookies[index]=value
			end

			def self.cookies
			  @cookies
			end

			def self.clear_cookies
				@cookies = {}
			end
  	end

  end
  
  before(:each) do
    Lacmus::Utils.restart_temp_user_ids
    Lacmus::SlotMachine.nuke_all_experiments
    Lacmus::Lab.clear_cookies
  end

  def create_and_activate_experiment
    experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
    Lacmus::SlotMachine.activate_experiment(experiment_id)
    experiment_id
  end

  def create_experiment
  	Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
  end

  it "should place different slots for different user ids" do
    create_and_activate_experiment
    first_user_slot = Lacmus::Lab.slot_for_user
    Lacmus::Lab.clear_cookies
    second_user_slot = Lacmus::Lab.slot_for_user
    Lacmus::Lab.clear_cookies
    third_user_slot = Lacmus::Lab.slot_for_user
    
    expect(first_user_slot).not_to eq(second_user_slot)
    expect(third_user_slot).to eq(first_user_slot)
  end

  it "should render different results for control and experiment groups (string)" do
    experiment_id = create_and_activate_experiment
    result1 = simple_experiment(experiment_id, "control", "experiment")
    expect(Lacmus::Lab.user_belongs_to_control_group?).to be_false
    expect(result1).to eq("experiment")
    Lacmus::Lab.clear_cookies

    result2 = Lacmus::Lab.simple_experiment(experiment_id, "control", "experiment")
    expect(Lacmus::Lab.user_belongs_to_control_group?).to be_true
    expect(result2).to eq("control")
  end

  it "should render different results for control and experiment groups (&block)" do
  	experiment_id = create_and_activate_experiment
  	block1 = Proc.new {|i| "text for block1"}
  	block2 = Proc.new {|i| "text for block2"}

		expect(Lacmus::Lab.user_belongs_to_control_group?).to be_false
  	result1 = Lacmus::Lab.render_control_version(experiment_id, &block1)
		expect(result1).to be_nil

  	result2 = Lacmus::Lab.render_experiment_version(experiment_id, &block2)
  	expect(result2).to eq("text for block2")
  	Lacmus::Lab.clear_cookies

		expect(Lacmus::Lab.user_belongs_to_control_group?).to be_true
  	result3 = Lacmus::Lab.render_control_version(experiment_id, &block1)
  	expect(result3).to eq("text for block1")

  	result4 = Lacmus::Lab.render_experiment_version(experiment_id, &block2)
  	expect(result4).to be_nil
  end

  it "should render control group if experiment isn't active (string)" do
  	experiment_id = create_experiment
  	result = Lacmus::Lab.simple_experiment(experiment_id, "control", "experiment")
  	expect(result).to eq("control")
  end

  it "should render control group if experiment isn't active (&block)" do
		experiment_id = create_experiment
		block = Proc.new {|i| "text for block"}

		expect(Lacmus::Lab.user_belongs_to_control_group?).to be_false
		result1 = Lacmus::Lab.render_control_version(experiment_id, &block)
		expect(result1).to eq("text for block")

  	result2 = Lacmus::Lab.render_experiment_version(experiment_id, &block)
  	expect(result2).to be_nil
  end

  # Moshe to Shai: probably not what you wanted to see here...
  it "should render experiment before and after cookie expired (string)" do
  	experiment_id = create_and_activate_experiment
  	expect(Lacmus::Lab.user_belongs_to_control_group?).to be_false

  	result = Lacmus::Lab.simple_experiment(experiment_id, "control", "experiment")
  	expect(result).to eq("experiment")
  	Lacmus::Lab.clear_cookies

  	result2 = Lacmus::Lab.simple_experiment(experiment_id, "control", "experiment")
  	expect(result2).to eq("control")
  end

  it "should render control group before and after cookie expired (&block)" do
  end

end