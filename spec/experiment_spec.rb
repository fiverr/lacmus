require 'spec_helper'
require 'lacmus'

include Lacmus::Lab

describe Lacmus::Experiment, "Experiment" do

  before(:all) do
  
    @experiment_name = "experimentum"
    @experiment_description = "dekaprius dela karma"
    @experiment_screenshot_url = "http://google.com"
    @cookies = {}
  end
  
  before(:each) do
    Lacmus.restart_temp_user_ids
    Lacmus::Experiment.nuke_all_experiments
    reset_active_experiments_cache
  end

  def new_experiment_attrs
  	attrs = {
  		:name 					=> @experiment_name,
  		:description 		=> @experiment_description,
  		:screenshot_url => @experiment_screenshot_url
  	}
  end

  def create_and_activate_experiment
  	exp_obj = Lacmus::Experiment.create!(new_experiment_attrs)
  	exp_obj.activate!
    exp_obj.id
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
  end

  def reset_instance_variables
  	@user_experiment = nil
  	@uid_hash = nil
  	reset_active_experiments_cache
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


  def reset_active_experiments_cache
		$__lcms__loaded_at_as_int = 0
	end

	describe "basic experiment functionality" do

		it "should create new experiment as pending with the given values" do
			exp_obj = Lacmus::Experiment.create!(new_experiment_attrs)
			expect(exp_obj.id).to be > 0
			expect(exp_obj.status).to eq(:pending)
			expect(exp_obj.name).to eq(@experiment_name)
			expect(exp_obj.description).to eq(@experiment_description)
		end

		it "should remove experiment from list" do 
			exp_obj = Lacmus::Experiment.create!(new_experiment_attrs)
			exp_obj.remove_from_list(:pending)

			experiment = Lacmus::Experiment.find_in_list(exp_obj.id, :pending)
			expect(experiment).to be_nil
		end

		it "should move experiment from pending to active" do 
			exp_obj = Lacmus::Experiment.create!(new_experiment_attrs)
			move_result = exp_obj.move_to_list(:active)
			expect(move_result).to be_true

			experiment_pending = Lacmus::Experiment.find_in_list(exp_obj.id, :pending)
			experiment_active = Lacmus::Experiment.find_in_list(exp_obj.id, :active)

			expect(experiment_pending).to be_nil
			expect(experiment_active.name).to eq(@experiment_name)
		end

		it "should set experiment end time after moving from active to completed" do 
			pending_exp = Lacmus::Experiment.create!(new_experiment_attrs)
			expect(pending_exp.end_time).to be_nil
			pending_exp.move_to_list(:active)
			pending_exp.move_to_list(:completed)

			completed_exp = Lacmus::Experiment.find_in_list(pending_exp.id, :completed)
			expect(completed_exp.end_time).not_to be_nil
		end

		it "should destroy experiment" do
			pending_exp = Lacmus::Experiment.create!(new_experiment_attrs)
			find_exp = Lacmus::Experiment.find_in_list(pending_exp.id, :pending)
			expect(find_exp).not_to be_nil

			Lacmus::Experiment.destroy(pending_exp.id)
			find_exp = Lacmus::Experiment.find_in_list(pending_exp.id, :pending)
			expect(find_exp).to be_nil
		end

		# TODO: write me!
		it "should change the experiment start time after restart" do
		end

	end # of describe "basic experiment functionality"

  it "should increment exposure counters for an active exeriment" do
    experiment_id = create_and_activate_experiment
    all_exposures_1 = get_exposures_for_experiment(experiment_id) + get_exposures_for_experiment(experiment_id, true)
    expect(all_exposures_1).to eq(0)
    simple_experiment(experiment_id, "control", "experiment")

    expect(user_belongs_to_control_group?).to be_false
    expect(get_exposures_for_experiment(experiment_id, true)).to eq(0)
    expect(get_exposures_for_experiment(experiment_id)).to eq(1)
  end

  it "should not increment exposure counters for a pending or completed experiment" do
  	exp_obj = Lacmus::Experiment.create!(new_experiment_attrs)
  	exp_id  = exp_obj.id

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

  it "should allow to update an experiment" do
    experiment_id = create_and_activate_experiment
    experiment = Lacmus::Experiment.find(experiment_id)
    expect(experiment.name).to eq(@experiment_name)
    expect(experiment.description).to eq(@experiment_description)
    expect(experiment.screenshot_url).to eq(@experiment_screenshot_url)

    experiment.name = "new name"
    experiment.description = "new description"
    experiment.screenshot_url = "new screenshot url"
    experiment.save

    loaded_experiment = Lacmus::Experiment.find(experiment_id)
    expect(loaded_experiment.name).to eq("new name")
    expect(loaded_experiment.description).to eq("new description")
    expect(loaded_experiment.screenshot_url).to eq("new screenshot url")
  end

  it "should increment KPIs only for a active experiments" do
    experiment_id = create_and_activate_experiment
    simple_experiment(experiment_id, "control", "experiment")
    exposures = get_exposures_for_experiment(experiment_id)
    expect(exposures).to eq(1)
    mark_kpi!('ftb')
    mark_kpi!('ftb')
    expect(get_kpis_for_experiment(experiment_id)['ftb'].to_i).to eq(2)
  end

  it "should calculate conversion correctly" do
    experiment_id = create_and_activate_experiment

    10.times do 
      simulate_unique_visitor_exposure(experiment_id)
    end

    2.times do
      mark_kpi!('ftb')
    end

    conversion = Lacmus::Experiment.find(experiment_id).experiment_conversion('ftb')
    expect(conversion).to eq(20)
  end

  it "should only add KPIs and exposures to the viewed experiment" do
    Lacmus::SlotMachine.resize_and_reset_slot_array(3)
    
    experiment_id1 = create_and_activate_experiment
    experiment_id2 = create_and_activate_experiment
    
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

  it "should only mark KPI if the experiment is active" do
  	experiment_id1 = create_and_activate_experiment
  	simulate_unique_visitor_exposure(experiment_id1)
  	exp_obj = Lacmus::Experiment.find(experiment_id1)
  	exp_obj.deactivate!

  	mark_kpi!('ftb')
  	expect(get_kpis_for_experiment(experiment_id1)['ftb'].to_i).to eq(0)
  end

  it "should not mark kpi for exposed experiment after reset" do
  	experiment_id1 = create_and_activate_experiment
  	simulate_unique_visitor_exposure(experiment_id1)

		# sleeping because the test runs too fast without it
		# and it'll not affect the experiment's start_time
		sleep 1
  	Lacmus::Experiment.find(experiment_id1).restart!
  	reset_active_experiments_cache
  	mark_kpi!('ftb')
  	expect(get_kpis_for_experiment(experiment_id1)['ftb'].to_i).to eq(0)
  end

  it "should not mark kpi for exposed experiment after reset" do
  	experiment_id1 = create_and_activate_experiment
  	simulate_unique_visitor_exposure(experiment_id1)

		# sleeping because the test runs too fast without it
		# and it'll not affect the experiment's start_time
		sleep 1
  	Lacmus::Experiment.find(experiment_id1).restart!
  	reset_active_experiments_cache
  	mark_kpi!('ftb')
  	expect(get_kpis_for_experiment(experiment_id1)['ftb'].to_i).to eq(0)
  end

  it "should mark 1 kpi for control user after restart" do
		experiment_id = create_and_activate_experiment
  	build_tuid_cookie(2)

		expect(user_belongs_to_control_group?).to be_true
		simple_experiment(experiment_id, "control", "experiment")
		cookie_value_before_restart = experiment_cookie_value

		# sleeping because the test runs too fast without it
		# and it'll not affect the experiment's start_time
		sleep 1
  	Lacmus::Experiment.find(experiment_id).restart!

  	simple_experiment(experiment_id, "control", "experiment")
  	cookie_value_after_restart = experiment_cookie_value
  	expect(cookie_value_before_restart).not_to eq(cookie_value_after_restart)

  	mark_kpi!('ftb')
  	expect(get_kpis_for_experiment(experiment_id, true)['ftb'].to_i).to eq(1)
  end

  it "should mark 1 kpi for experiment user after restart" do
		experiment_id = create_and_activate_experiment
		build_tuid_cookie(1)

		expect(user_belongs_to_control_group?).to be_false
		simple_experiment(experiment_id, "control", "experiment")
		cookie_value_before_restart = experiment_cookie_value

		# sleeping because the test runs too fast without it
		# and it'll not affect the experiment's start_time
		sleep 1
  	Lacmus::Experiment.find(experiment_id).restart!

  	simple_experiment(experiment_id, "control", "experiment")
  	cookie_value_after_restart = experiment_cookie_value
  	expect(cookie_value_before_restart).not_to eq(cookie_value_after_restart)

  	mark_kpi!('ftb')
  	expect(get_kpis_for_experiment(experiment_id)['ftb'].to_i).to eq(1)
  end

end