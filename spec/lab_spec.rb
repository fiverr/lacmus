require 'spec_helper'
require 'lacmus'

include Lacmus::Lab

describe Lacmus::Lab, "Lab" do

	before(:all) do
  
    @experiment_name = "experimentum"
    @experiment_description = "dekaprius dela karma"
    @cookies = {}

  end
  
  before(:each) do
    Lacmus.restart_temp_user_ids
    Lacmus::Experiment.nuke_all_experiments
    @cookies = {}
    reset_active_experiments_cache
  end

  # ----------------------------------------------------------------
  # HELPER METHODS
  # ----------------------------------------------------------------

  def create_and_activate_experiment
		exp_obj = create_experiment
  	exp_obj.activate!
    exp_obj
  end

  def create_experiment
  	Lacmus::Experiment.create!({name: @experiment_name, description: @experiment_description})
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

  def get_exposures_for_experiment(experiment_id, is_control = false)
    obj = Lacmus::Experiment.find(experiment_id)
    return obj.control_analytics[:exposures].to_i if is_control
    obj.experiment_analytics[:exposures].to_i
  end

  def get_kpis_for_experiment(experiment_id, is_control = false)
    experiment = Lacmus::Experiment.find(experiment_id)
    is_control ? experiment.control_kpis : experiment.experiment_kpis
  end

  def simulate_unique_visitor_exposure(experiment_id)
    clear_cookies
    simple_experiment(experiment_id, "control", "experiment")
  end

  # ----------------------------------------------------------------

  describe "Basic slots functionality" do

  	it "should place different slots for different user ids" do
	    create_and_activate_experiment.id
	    first_user_slot = slot_for_user

	    clear_cookies
	    second_user_slot = slot_for_user

	    clear_cookies
	    third_user_slot = slot_for_user
	    
	    expect(first_user_slot).not_to eq(second_user_slot)
	    expect(third_user_slot).to eq(first_user_slot)
	  end

  end # of describe "Basic slots functionality"

  describe "Functionality for render simple experiment using string" do

  	it "should render different results for control and experiment groups" do
	    experiment_id = create_and_activate_experiment.id
	    result1 = simple_experiment(experiment_id, "control", "experiment")
	    expect(user_belongs_to_control_group?).to be_false
	    expect(result1).to eq("experiment")
	    clear_cookies

	    result2 = simple_experiment(experiment_id, "control", "experiment")
	    expect(user_belongs_to_control_group?).to be_true
	    expect(result2).to eq("control")
	  end

	  it "should render control group if experiment isn't active" do
	  	experiment_id = create_experiment.id
	  	result = simple_experiment(experiment_id, "control", "experiment")
	  	expect(result).to eq("control")
	  end

	  it "should render experiment before and after cookie expired" do
	  	experiment_id = create_and_activate_experiment.id
	  	expect(user_belongs_to_control_group?).to be_false

	  	result = simple_experiment(experiment_id, "control", "experiment")
	  	expect(result).to eq("experiment")
	  	clear_cookies

	  	result2 = simple_experiment(experiment_id, "control", "experiment")
	  	expect(result2).to eq("control")
	  end

	  it "should not increment exposure counters for a pending or completed experiment" do
	  	exp_obj = create_experiment
	  	exp_id 	= exp_obj.id

	    simple_experiment(exp_id, "control", "experiment")
	    pending_experiment_exposures = get_exposures_for_experiment(exp_id) + get_exposures_for_experiment(exp_id, true)
	    expect(pending_experiment_exposures).to eq(0)

	    reset_instance_variables
	    exp_obj.activate!
	    simple_experiment(exp_id, "control", "experiment")
	    active_experiment_exposures = get_exposures_for_experiment(exp_id) + get_exposures_for_experiment(exp_id, true)
	    expect(active_experiment_exposures).to eq(1)

	    reset_instance_variables
	    exp_obj.deactivate!
	    simple_experiment(exp_id, "control", "experiment")
	    completed_experiment_exposures = get_exposures_for_experiment(exp_id) + get_exposures_for_experiment(exp_id, true)
	    expect(completed_experiment_exposures).to eq(1)
	  end

	  it "should increment views for exeperiments the user was exposed to (control group)" do
	    Lacmus::SlotMachine.resize_and_reset_slot_array(3)
	    Lacmus::SlotMachine.reset_worker_cache

	    experiment_id1 = create_and_activate_experiment.id
	    experiment_id2 = create_and_activate_experiment.id
			2.times { current_temp_user_id; clear_cookies}
			current_temp_user_id
	    expect(user_belongs_to_control_group?).to be_true

	    simple_experiment(experiment_id1, "control", "experiment")
	    expect(Lacmus::Experiment.find(experiment_id1).control_analytics[:exposures].to_i).to eq(1)
	    expect(Lacmus::Experiment.find(experiment_id2).control_analytics[:exposures].to_i).to eq(0)

	    simple_experiment(experiment_id2, "control", "experiment")
	    expect(Lacmus::Experiment.find(experiment_id1).control_analytics[:exposures].to_i).to eq(1)
	    expect(Lacmus::Experiment.find(experiment_id2).control_analytics[:exposures].to_i).to eq(1)
	  end

	  it "should increment views for exeperiments the user was exposed to (non-control group)" do
	    Lacmus::SlotMachine.resize_and_reset_slot_array(3)
	    Lacmus::SlotMachine.reset_worker_cache

	    experiment_id1 = create_and_activate_experiment.id
	    experiment_id2 = create_and_activate_experiment.id
	    expect(user_belongs_to_control_group?).to be_false
	    expect(user_belongs_to_experiment?(experiment_id1)).to be_true

	    simple_experiment(experiment_id1, "control", "experiment")
	    expect(Lacmus::Experiment.find(experiment_id1).experiment_analytics[:exposures].to_i).to eq(1)
	    expect(Lacmus::Experiment.find(experiment_id2).experiment_analytics[:exposures].to_i).to eq(0)

	    expect(Lacmus::Experiment.find(experiment_id1).control_analytics[:exposures].to_i).to eq(0)
	    expect(Lacmus::Experiment.find(experiment_id2).control_analytics[:exposures].to_i).to eq(0)

	    simple_experiment(experiment_id2, "control", "experiment")
	    expect(Lacmus::Experiment.find(experiment_id1).experiment_analytics[:exposures].to_i).to eq(1)
	    expect(Lacmus::Experiment.find(experiment_id2).experiment_analytics[:exposures].to_i).to eq(0)

	    expect(Lacmus::Experiment.find(experiment_id1).control_analytics[:exposures].to_i).to eq(0)
	    expect(Lacmus::Experiment.find(experiment_id2).control_analytics[:exposures].to_i).to eq(0)
	  end

	  it "should change the cookie's prefix is user switched to control group after resize" do
			experiment_id = create_and_activate_experiment.id

			build_tuid_cookie(3)
	  	expect(user_belongs_to_control_group?).to be_false
	  	simple_experiment(experiment_id, "control", "experiment")
	  	expect(control_group_prefix?).to be_false

	  	Lacmus::SlotMachine.resize_and_reset_slot_array(3)
	  	Lacmus::SlotMachine.reset_worker_cache

	  	experiment_id2 = create_and_activate_experiment.id
	  	expect(user_belongs_to_control_group?).to be_true

	  	simple_experiment(experiment_id2, "control", "experiment")
	  	expect(control_group_prefix?).to be_true
	  end

	  it "should increment KPIs for active experiments only" do
	    experiment = create_and_activate_experiment
	    experiment_id = experiment.id

	    simple_experiment(experiment_id, "control", "experiment")
	    exposures = get_exposures_for_experiment(experiment_id)
	    expect(exposures).to eq(1)
	    mark_kpi!('ftb')
	    mark_kpi!('ftb')
	    expect(get_kpis_for_experiment(experiment_id)['ftb'].to_i).to eq(2)

			experiment.deactivate!
			mark_kpi!('ftb')
	    expect(get_kpis_for_experiment(experiment_id)['ftb'].to_i).to eq(2)
	  end

	  it "should only add KPIs and exposures to the viewed experiment" do
	    Lacmus::SlotMachine.resize_and_reset_slot_array(4)
	    Lacmus::SlotMachine.reset_worker_cache
	    
	    experiment_id1 = create_and_activate_experiment.id
	    experiment_id2 = create_and_activate_experiment.id

	    simulate_unique_visitor_exposure(experiment_id1)
	    simulate_unique_visitor_exposure(experiment_id1)
	    simulate_unique_visitor_exposure(experiment_id1)

	    mark_kpi!('ftb')
	    mark_kpi!('ftb')
	    mark_kpi!('ftb')

	    expect(get_exposures_for_experiment(experiment_id1).to_i).to eq(3)
	    expect(get_exposures_for_experiment(experiment_id2).to_i).to eq(0)

	    expect(get_kpis_for_experiment(experiment_id1)['ftb'].to_i).to eq(3)
	    expect(get_kpis_for_experiment(experiment_id2)['ftb'].to_i).to eq(0)
	  end

  end # of describe "Functionality for render simple experiment using string"

  describe "Functionality for render experiment using block" do

		it "should render different results for control and experiment groups" do
	  	experiment_id = create_and_activate_experiment.id
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

	  it "should render control group if experiment isn't active" do
			experiment_id = create_experiment.id
			block = Proc.new {|i| "text for block"}

			expect(user_belongs_to_control_group?).to be_false
			result1 = render_control_version(experiment_id, &block)
			expect(result1).to eq("text for block")

	  	result2 = render_experiment_version(experiment_id, &block)
	  	expect(result2).to be_nil
	  end

	  it "should increment views for exeperiments the user was exposed to (control group)" do
	    Lacmus::SlotMachine.resize_and_reset_slot_array(3)
	    Lacmus::SlotMachine.reset_worker_cache

	    experiment_id1 = create_and_activate_experiment.id
	    experiment_id2 = create_and_activate_experiment.id
			2.times { current_temp_user_id; clear_cookies}
			current_temp_user_id
	    expect(user_belongs_to_control_group?).to be_true

	    render_control_version(experiment_id1) do
	     	"control"
	   	end

	    expect(Lacmus::Experiment.find(experiment_id1).control_analytics[:exposures].to_i).to eq(1)
	    expect(Lacmus::Experiment.find(experiment_id2).control_analytics[:exposures].to_i).to eq(0)

	    simple_experiment(experiment_id2, "control", "experiment")
	    expect(Lacmus::Experiment.find(experiment_id1).control_analytics[:exposures].to_i).to eq(1)
	    expect(Lacmus::Experiment.find(experiment_id2).control_analytics[:exposures].to_i).to eq(1)
	  end

	  it "should increment views for exeperiments the user was exposed to (non-control group)" do
	    Lacmus::SlotMachine.resize_and_reset_slot_array(3)
	    Lacmus::SlotMachine.reset_worker_cache

	    experiment_id1 = create_and_activate_experiment.id
	    experiment_id2 = create_and_activate_experiment.id
	    expect(user_belongs_to_control_group?).to be_false
	    expect(user_belongs_to_experiment?(experiment_id1)).to be_true

	    render_experiment_version(experiment_id1) do
	     	"experiment"
	   	end

	    expect(Lacmus::Experiment.find(experiment_id1).experiment_analytics[:exposures].to_i).to eq(1)
	    expect(Lacmus::Experiment.find(experiment_id2).experiment_analytics[:exposures].to_i).to eq(0)

	    expect(Lacmus::Experiment.find(experiment_id1).control_analytics[:exposures].to_i).to eq(0)
	    expect(Lacmus::Experiment.find(experiment_id2).control_analytics[:exposures].to_i).to eq(0)

	    render_experiment_version(experiment_id2) do
	     	"experiment"
	   	end

	    expect(Lacmus::Experiment.find(experiment_id1).experiment_analytics[:exposures].to_i).to eq(1)
	    expect(Lacmus::Experiment.find(experiment_id2).experiment_analytics[:exposures].to_i).to eq(0)

	    expect(Lacmus::Experiment.find(experiment_id1).control_analytics[:exposures].to_i).to eq(0)
	    expect(Lacmus::Experiment.find(experiment_id2).control_analytics[:exposures].to_i).to eq(0)
	  end

  end # of describe "Functionality for render experiment using block"

end