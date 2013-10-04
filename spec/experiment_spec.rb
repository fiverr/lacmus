require 'spec_helper'
require 'lacmus'

include Lacmus::Lab

describe Lacmus::Experiment, "Experiment" do
  
  before(:each) do
    Lacmus.restart_user_ids_counter
    Lacmus::Experiment.nuke_all_experiments
    clear_cookies
    reset_active_experiments_cache
  end

  describe "Basic functionality" do

    it "should create new experiment as pending with the given values" do
      exp_obj = create_experiment
      expect(exp_obj.id).to be > 0
      expect(exp_obj.status).to eq(:pending)
      expect(exp_obj.name).to eq(EXPERIMENT_NAME)
      expect(exp_obj.description).to eq(EXPERIMENT_DESCRIPTION)
    end

    it "should remove experiment from list" do 
      exp_obj = create_experiment
      exp_obj.remove_from_list(:pending)

      experiment = Lacmus::Experiment.find_in_list(exp_obj.id, :pending)
      expect(experiment).to be_nil
    end

    it "should move experiment from pending to active" do 
      exp_obj = create_experiment
      move_result = exp_obj.move_to_list(:active)
      expect(move_result).to be_true

      experiment_pending = Lacmus::Experiment.find_in_list(exp_obj.id, :pending)
      experiment_active = Lacmus::Experiment.find_in_list(exp_obj.id, :active)

      expect(experiment_pending).to be_nil
      expect(experiment_active.name).to eq(EXPERIMENT_NAME)
    end

    it "should set experiment end time after moving from active to completed" do 
      pending_exp = create_experiment
      expect(pending_exp.end_time).to be_nil
      pending_exp.move_to_list(:active)
      pending_exp.move_to_list(:completed)

      completed_exp = Lacmus::Experiment.find_in_list(pending_exp.id, :completed)
      expect(completed_exp.end_time).not_to be_nil
    end

    it "should destroy experiment" do
      pending_exp = create_experiment
      find_exp = Lacmus::Experiment.find_in_list(pending_exp.id, :pending)
      expect(find_exp).not_to be_nil

      Lacmus::Experiment.destroy(pending_exp.id)
      find_exp = Lacmus::Experiment.find_in_list(pending_exp.id, :pending)
      expect(find_exp).to be_nil
    end

    it "should change the experiment start time after restart" do
      exp = create_and_activate_experiment
      start_time = exp.start_time
      expect(start_time).not_to be_nil

      sleep 1 # sleeping to force incrementation of experiment's start time 
      exp.restart!

      start_time_after_restart = exp.start_time
      expect(start_time_after_restart).not_to be_nil
      expect(start_time_after_restart).not_to eq(start_time)
    end

    it "should update an experiment" do
      experiment_id = create_and_activate_experiment.id
      experiment = Lacmus::Experiment.find(experiment_id)
      expect(experiment.name).to eq(EXPERIMENT_NAME)
      expect(experiment.description).to eq(EXPERIMENT_DESCRIPTION)
      expect(experiment.screenshot_url).to eq(EXPERIMENT_SCREENSHOT_URL)

      experiment.name = "new name"
      experiment.description = "new description"
      experiment.screenshot_url = "new screenshot url"
      experiment.save

      loaded_experiment = Lacmus::Experiment.find(experiment_id)
      expect(loaded_experiment.name).to eq("new name")
      expect(loaded_experiment.description).to eq("new description")
      expect(loaded_experiment.screenshot_url).to eq("new screenshot url")
    end

    it 'should add completed experiment to recent_completed_experiments list' do
      experiment = create_and_activate_experiment
      experiment.deactivate!
      expect(Lacmus::Experiment.recent_completed_experiments).to include(experiment.id.to_s)
    end

  end # of describe "Basic functionality"

  describe 'Analytics' do

    it 'should calculate conversion correctly for control group user' do
      experiment_id = create_and_activate_experiment.id

      10.times do 
        simulate_unique_visitor_exposure(experiment_id)
      end

      2.times do
        mark_kpi!('ftb')
      end

      control_conversion = Lacmus::Experiment.find(experiment_id).control_conversion('ftb')
      expect(control_conversion).to eq(40)

      experiment_conversion = Lacmus::Experiment.find(experiment_id).experiment_conversion('ftb')     
      expect(experiment_conversion).to eq(0)
    end

    it 'should record kpis for each experiment and each kpi on a timeline' do
      experiment_id = create_and_activate_experiment.id

      2.times do
        simulate_unique_visitor_exposure(experiment_id)
      end

			expect(user_belongs_to_control_group?).to be_true

      2.times do
        mark_kpi!('ftb')
      end

      experiment = Lacmus::Experiment.find(experiment_id)
      result = experiment.kpi_timeline_data('ftb', true)[0]
      expect(result[1]).to eq(2)
    end

    it 'should calculate conversion timeline data' do
    	experiment_id = create_and_activate_experiment.id

      2.times do
        simulate_unique_visitor_exposure(experiment_id)
      end

			expect(user_belongs_to_control_group?).to be_true

      2.times do
        mark_kpi!('ftb')
      end

      experiment = Lacmus::Experiment.find(experiment_id)
      expect(experiment.conversion_timeline_data('ftb', true)).to eq([])
      expect(experiment.conversion_timeline_data('ftb', false)).to eq([])
    end

    it 'should record hourly views' do
			experiment_id = create_and_activate_experiment.id

      10.times do
        simulate_unique_visitor_exposure(experiment_id)
      end

			experiment = Lacmus::Experiment.find(experiment_id)
      expect(experiment.views_timeline_data(true)[0][1]).to eq(5)
      expect(experiment.views_timeline_data(false)[0][1]).to eq(5)
    end

    it 'should calculate conversion correctly for experiment group user' do
      experiment_id = create_and_activate_experiment.id

      9.times do 
        simulate_unique_visitor_exposure(experiment_id)
      end

      2.times do
        mark_kpi!('ftb')
      end

      control_conversion = Lacmus::Experiment.find(experiment_id).control_conversion('ftb')
      expect(control_conversion).to eq(0)

      experiment_conversion = Lacmus::Experiment.find(experiment_id).experiment_conversion('ftb')     
      expect(experiment_conversion).to eq(40)
    end

  end # of describe 'Analytics'

end # of describe Lacmus::Experiment, "Experiment"