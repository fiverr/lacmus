require 'lacmus'
include Lacmus::Lab

describe Lacmus::Lab, "Lab" do

	before(:all) do
  
    @experiment_name = "experimentum"
    @experiment_description = "dekaprius dela karma"
    @cookies = {}

  end
  
  before(:each) do
    Lacmus::Utils.restart_temp_user_ids
    Lacmus::SlotMachine.nuke_all_experiments
    @cookies = {}
    reset_active_experiments_cache
  end

  def create_and_activate_experiment
    experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
    Lacmus::SlotMachine.activate_experiment(experiment_id)
    experiment_id
  end

  def reset_active_experiments_cache
		$__lcms__loaded_at_as_int = 0
	end

  def [](index)
	  @cookies[index]
	end

	def []=(index,value)
	  @cookies[index]=value
	end

	def cookies
	  @cookies
	end

	def clear_cookies
		@cookies = {}
		@uid_hash = {}
	end

	def reset_instance_variables
		@user_experiment = nil
  	@rendered_control_group = nil
  end

  def create_experiment
  	Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
  end

  it "should place different slots for different user ids" do
    create_and_activate_experiment
    first_user_slot = slot_for_user

    clear_cookies
    second_user_slot = slot_for_user

    clear_cookies
    third_user_slot = slot_for_user
    
    expect(first_user_slot).not_to eq(second_user_slot)
    expect(third_user_slot).to eq(first_user_slot)
  end

  it "should render different results for control and experiment groups (string)" do
    experiment_id = create_and_activate_experiment
    result1 = simple_experiment(experiment_id, "control", "experiment")
    expect(user_belongs_to_control_group?).to be_false
    expect(result1).to eq("experiment")
    clear_cookies

    result2 = simple_experiment(experiment_id, "control", "experiment")
    expect(user_belongs_to_control_group?).to be_true
    expect(result2).to eq("control")
  end

  it "should render different results for control and experiment groups (&block)" do
  	experiment_id = create_and_activate_experiment
  	block1 = Proc.new {|i| "text for block1"}
  	block2 = Proc.new {|i| "text for block2"}

		expect(user_belongs_to_control_group?).to be_false
  	result1 = render_control_version(experiment_id, &block1)
		expect(result1).to be_nil

  	reset_instance_variables
  	result2 = render_experiment_version(experiment_id, &block2)
  	expect(result2).to eq("text for block2")
  	clear_cookies

		expect(user_belongs_to_control_group?).to be_true
		reset_instance_variables
  	result3 = render_control_version(experiment_id, &block1)
  	expect(result3).to eq("text for block1")

  	reset_instance_variables
  	result4 = render_experiment_version(experiment_id, &block2)
  	expect(result4).to be_nil
  end

  it "should render control group if experiment isn't active (string)" do
  	experiment_id = create_experiment
  	result = simple_experiment(experiment_id, "control", "experiment")
  	expect(result).to eq("control")
  end

  it "should render control group if experiment isn't active (&block)" do
		experiment_id = create_experiment
		block = Proc.new {|i| "text for block"}

		expect(user_belongs_to_control_group?).to be_false
		result1 = render_control_version(experiment_id, &block)
		expect(result1).to eq("text for block")

  	result2 = render_experiment_version(experiment_id, &block)
  	expect(result2).to be_nil
  end

  it "should render experiment before and after cookie expired (string)" do
  	experiment_id = create_and_activate_experiment
  	expect(user_belongs_to_control_group?).to be_false

  	result = simple_experiment(experiment_id, "control", "experiment")
  	expect(result).to eq("experiment")
  	clear_cookies

  	result2 = simple_experiment(experiment_id, "control", "experiment")
  	expect(result2).to eq("control")
  end

  it "control group user should only increment views and kpis for exeperiments he was exposed to" do
    Lacmus::SlotMachine.worker_cache_active = false
    Lacmus::SlotMachine.resize_slot_array(3)
    # reset_active_experiments_cache

    experiment_id1 = create_and_activate_experiment
    experiment_id2 = create_and_activate_experiment
    p "initial uid: #{current_temp_user_id}"

    2.times {p current_temp_user_id; clear_cookies}
    p "final uid: #{current_temp_user_id}"
    p "slot count: #{Lacmus::SlotMachine.experiment_slots.count}"
    expect(user_belongs_to_control_group?).to be_true

    simple_experiment(experiment_id1, "control", "experiment")
    expect(Lacmus::Experiment.new(experiment_id1).control_analytics[:exposures].to_i).to eq(1)
    expect(Lacmus::Experiment.new(experiment_id2).control_analytics[:exposures].to_i).to eq(0)
  end

end