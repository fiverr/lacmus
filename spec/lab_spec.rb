require 'spec_helper'
require 'lacmus'

include Lacmus::Lab

describe Lacmus::Lab, "Lab" do
  
  before(:each) do
    Lacmus.restart_user_ids_counter
    Lacmus::Experiment.nuke_all_experiments
    clear_cookies
    reset_active_experiments_cache
  end

  # ----------------------------------------------------------------
  # HELPER METHODS
  # ----------------------------------------------------------------

  def get_exposures_for_experiment(experiment_id, is_control = false)
    obj = Lacmus::Experiment.find(experiment_id)
    return obj.control_analytics[:exposures].to_i if is_control
    obj.experiment_analytics[:exposures].to_i
  end

  def get_kpis_for_experiment(experiment_id, is_control = false)
    experiment = Lacmus::Experiment.find(experiment_id)
    is_control ? experiment.control_kpis : experiment.experiment_kpis
  end

  # ----------------------------------------------------------------

  # describe "Basic slots functionality" do

  #   it "should place different slots for different user ids" do
  #     create_and_activate_experiment.id
  #     first_user_slot = slot_for_user

  #     clear_cookies_and_uid_hash
  #     second_user_slot = slot_for_user

  #     clear_cookies_and_uid_hash
  #     third_user_slot = slot_for_user
      
  #     expect(first_user_slot).not_to eq(second_user_slot)
  #     expect(third_user_slot).to eq(first_user_slot)
  #   end

  # end # of describe "Basic slots functionality"

  # describe "Functionality for render simple experiment using string" do

  #   it "should render different results for control and experiment groups" do
  #     experiment_id = create_and_activate_experiment.id
  #     result1 = simple_experiment(experiment_id, "control", "experiment")
  #     expect(user_belongs_to_control_group?).to be_false
  #     expect(result1).to eq("experiment")
  #     clear_cookies_and_uid_hash

  #     result2 = simple_experiment(experiment_id, "control", "experiment")
  #     expect(user_belongs_to_control_group?).to be_true
  #     expect(result2).to eq("control")
  #   end

  #   it "should render control group if experiment isn't active" do
  #     experiment_id = create_experiment.id
  #     result = simple_experiment(experiment_id, "control", "experiment")
  #     expect(result).to eq("control")
  #   end

  #   it "should render experiment before and after cookie expired" do
  #     experiment_id = create_and_activate_experiment.id
  #     expect(user_belongs_to_control_group?).to be_false

  #     result = simple_experiment(experiment_id, "control", "experiment")
  #     expect(result).to eq("experiment")
  #     clear_cookies_and_uid_hash

  #     result2 = simple_experiment(experiment_id, "control", "experiment")
  #     expect(result2).to eq("control")
  #   end

  #   it "should not increment exposure counters for a pending or completed experiment" do
  #     exp_obj = create_experiment
  #     exp_id  = exp_obj.id

  #     simple_experiment(exp_id, "control", "experiment")
  #     pending_experiment_exposures = get_exposures_for_experiment(exp_id) + get_exposures_for_experiment(exp_id, true)
  #     expect(pending_experiment_exposures).to eq(0)

  #     reset_instance_variables
  #     exp_obj.activate!
  #     simple_experiment(exp_id, "control", "experiment")
  #     active_experiment_exposures = get_exposures_for_experiment(exp_id) + get_exposures_for_experiment(exp_id, true)
  #     expect(active_experiment_exposures).to eq(1)

  #     reset_instance_variables
  #     exp_obj.deactivate!
  #     simple_experiment(exp_id, "control", "experiment")
  #     completed_experiment_exposures = get_exposures_for_experiment(exp_id) + get_exposures_for_experiment(exp_id, true)
  #     expect(completed_experiment_exposures).to eq(1)
  #   end

  #   it "should increment views for exeperiments the user was exposed to (control group)" do
  #     Lacmus::SlotMachine.resize_and_reset_slot_array(3)
  #     Lacmus::SlotMachine.reset_worker_cache

  #     experiment_id1 = create_and_activate_experiment.id
  #     experiment_id2 = create_and_activate_experiment.id
  #     build_tuid_cookie(3)
  #     expect(user_belongs_to_control_group?).to be_true

  #     simple_experiment(experiment_id1, "control", "experiment")
  #     expect(Lacmus::Experiment.find(experiment_id1).control_analytics[:exposures].to_i).to eq(1)
  #     expect(Lacmus::Experiment.find(experiment_id2).control_analytics[:exposures].to_i).to eq(0)

  #     simple_experiment(experiment_id2, "control", "experiment")
  #     expect(Lacmus::Experiment.find(experiment_id1).control_analytics[:exposures].to_i).to eq(1)
  #     expect(Lacmus::Experiment.find(experiment_id2).control_analytics[:exposures].to_i).to eq(1)
  #   end

  #   it "should increment views for exeperiments the user was exposed to (non-control group)" do
  #     Lacmus::SlotMachine.resize_and_reset_slot_array(3)
  #     Lacmus::SlotMachine.reset_worker_cache

  #     experiment_id1 = create_and_activate_experiment.id
  #     experiment_id2 = create_and_activate_experiment.id
  #     expect(user_belongs_to_control_group?).to be_false
  #     expect(user_belongs_to_experiment?(experiment_id1)).to be_true

  #     simple_experiment(experiment_id1, "control", "experiment")
  #     expect(Lacmus::Experiment.find(experiment_id1).experiment_analytics[:exposures].to_i).to eq(1)
  #     expect(Lacmus::Experiment.find(experiment_id2).experiment_analytics[:exposures].to_i).to eq(0)

  #     expect(Lacmus::Experiment.find(experiment_id1).control_analytics[:exposures].to_i).to eq(0)
  #     expect(Lacmus::Experiment.find(experiment_id2).control_analytics[:exposures].to_i).to eq(0)

  #     simple_experiment(experiment_id2, "control", "experiment")
  #     expect(Lacmus::Experiment.find(experiment_id1).experiment_analytics[:exposures].to_i).to eq(1)
  #     expect(Lacmus::Experiment.find(experiment_id2).experiment_analytics[:exposures].to_i).to eq(0)

  #     expect(Lacmus::Experiment.find(experiment_id1).control_analytics[:exposures].to_i).to eq(0)
  #     expect(Lacmus::Experiment.find(experiment_id2).control_analytics[:exposures].to_i).to eq(0)
  #   end

  #   it "should change the cookie's prefix is user switched to control group after resize" do
  #     experiment_id = create_and_activate_experiment.id

  #     build_tuid_cookie(3)
  #     expect(user_belongs_to_control_group?).to be_false
  #     simple_experiment(experiment_id, "control", "experiment")
  #     expect(control_group_prefix?).to be_false

  #     Lacmus::SlotMachine.resize_and_reset_slot_array(3)
  #     Lacmus::SlotMachine.reset_worker_cache

  #     experiment_id2 = create_and_activate_experiment.id
  #     expect(user_belongs_to_control_group?).to be_true

  #     simple_experiment(experiment_id2, "control", "experiment")
  #     expect(control_group_prefix?).to be_true
  #   end

  #   it "should mark KPI for active experiment" do
  #     experiment = create_and_activate_experiment
  #     experiment_id = experiment.id

  #     simple_experiment(experiment_id, "control", "experiment")
  #     exposures = get_exposures_for_experiment(experiment_id)
  #     expect(exposures).to eq(1)
  #     mark_kpi!('ftb')
  #     mark_kpi!('ftb')
  #     expect(get_kpis_for_experiment(experiment_id)['ftb'].to_i).to eq(2)
  #   end

  #   it "should not mark KPI for deactivated experiment" do
  #     experiment_id1 = create_and_activate_experiment.id
  #     simulate_unique_visitor_exposure(experiment_id1)
  #     Lacmus::Experiment.find(experiment_id1).deactivate!

  #     mark_kpi!('ftb')
  #     expect(get_kpis_for_experiment(experiment_id1)['ftb'].to_i).to eq(0)
  #   end

  #   it "should mark KPIs and exposures to exposed experiments" do
  #     Lacmus::SlotMachine.resize_and_reset_slot_array(4)
  #     Lacmus::SlotMachine.reset_worker_cache
      
  #     experiment_id1 = create_and_activate_experiment.id
  #     experiment_id2 = create_and_activate_experiment.id

  #     simulate_unique_visitor_exposure(experiment_id1)
  #     simulate_unique_visitor_exposure(experiment_id1)
  #     simulate_unique_visitor_exposure(experiment_id1)

  #     mark_kpi!('ftb')
  #     mark_kpi!('ftb')
  #     mark_kpi!('ftb')

  #     expect(get_exposures_for_experiment(experiment_id1).to_i).to eq(3)
  #     expect(get_exposures_for_experiment(experiment_id2).to_i).to eq(0)

  #     expect(get_kpis_for_experiment(experiment_id1)['ftb'].to_i).to eq(3)
  #     expect(get_kpis_for_experiment(experiment_id2)['ftb'].to_i).to eq(0)
  #   end

  #   it "should not mark kpi for control group user after reset" do
  #     experiment_id1 = create_and_activate_experiment.id
  #     expect(user_belongs_to_control_group?).to be_false
  #     simulate_unique_visitor_exposure(experiment_id1)

  #     sleep 1 # sleeping to force incrementation of experiment's start time 
  #     Lacmus::Experiment.find(experiment_id1).restart!

  #     mark_kpi!('ftb')
  #     expect(get_kpis_for_experiment(experiment_id1)['ftb'].to_i).to eq(0)
  #   end

  #   it "should not mark kpi for experiment group user after reset" do
  #     experiment_id1 = create_and_activate_experiment.id
  #     build_tuid_cookie(2)
  #     expect(user_belongs_to_control_group?).to be_true
  #     simulate_unique_visitor_exposure(experiment_id1)

  #     sleep 1 # sleeping to force incrementation of experiment's start time 
  #     Lacmus::Experiment.find(experiment_id1).restart!

  #     mark_kpi!('ftb')
  #     expect(get_kpis_for_experiment(experiment_id1, true)['ftb'].to_i).to eq(0)
  #   end

  #   it "should mark kpi for control group user after restart and re-exposure" do
  #     experiment_id = create_and_activate_experiment.id
  #     build_tuid_cookie(2)
  #     expect(user_belongs_to_control_group?).to be_true
  #     simple_experiment(experiment_id, "control", "experiment")

  #     sleep 1 # sleeping to force incrementation of experiment's start time 
  #     Lacmus::Experiment.find(experiment_id).restart!
  #     simple_experiment(experiment_id, "control", "experiment")

  #     mark_kpi!('ftb')
  #     expect(get_kpis_for_experiment(experiment_id, true)['ftb'].to_i).to eq(1)
  #   end

  #   it "should mark kpi for experiment group user after restart and re-exposure" do
  #     experiment_id = create_and_activate_experiment.id
  #     expect(user_belongs_to_control_group?).to be_false
  #     simple_experiment(experiment_id, "control", "experiment")

  #     sleep 1 # sleeping to force incrementation of experiment's start time 
  #     Lacmus::Experiment.find(experiment_id).restart!
  #     simple_experiment(experiment_id, "control", "experiment")

  #     mark_kpi!('ftb')
  #     expect(get_kpis_for_experiment(experiment_id)['ftb'].to_i).to eq(1)
  #   end

  #   it "should update the experiment cookie" do
  #     # cookie_value_before_restart = experiment_cookie_value
  #     # cookie_value_after_restart = experiment_cookie_value
  #     # expect(cookie_value_before_restart).not_to eq(cookie_value_after_restart)
  #   end

  # end # of describe "Functionality for render simple experiment using string"

  describe "Functionality for render experiment using block" do

    it "should render different results for control and experiment variations" do
      experiment_id = create_and_activate_experiment.id
      block1 = Proc.new {|i| "text for block1"}
      block2 = Proc.new {|i| "text for block2"}

      expect(user_belongs_to_control_variation?(experiment_id)).to be_false
      result1 = render_be_control_variation(experiment_id, &block1)
      expect(result1).to be_nil

      reset_instance_variables
      result2 = render_experiment_version(experiment_id, &block2)
      expect(result2).to eq("text for block2")
      clear_cookies_and_uid_hash

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
      build_tuid_cookie(3)
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

  describe 'Functionality of AsyncLab' do

    before do
      set_alternative_user_id(700)
    end

    it 'should reflect that alternative user id was set' do
      experiment_id1 = create_and_activate_experiment.id
      simple_experiment(experiment_id1, "control", "experiment")
      Lacmus::AsyncLab.mark_kpi!('new_order', 700)

      expect(get_kpis_for_experiment(experiment_id1, false)['new_order'].to_i).to eq(1)
    end

  end # of describe 'Functionality of AsyncLa'

  describe 'Lacmus cache keys' do

    it 'should include control group as available cache key' do
      expect(available_lacmus_cache_keys).to include('0')
    end

  end # of describe 'Lacmus cache keys'

end # of describe Lacmus::Lab, "Lab"