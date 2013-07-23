require 'lacmus'
include Lacmus::Lab

describe Lacmus::Experiment, "Experiment" do

  before(:all) do
  
    @experiment_name = "experimentum"
    @experiment_description = "dekaprius dela karma"
    @experiment_screenshot_url = "http://google.com"
    @cookies = {}
    # self.class.instance_eval do
    #   @cookies = {}

    #   def self.[](index)
    #     @cookies[index]
    #   end

    #   def self.[]=(index,value)
    #     @cookies[index]=value
    #   end

    #   def self.cookies
    #     @cookies
    #   end

    #   def self.clear_cookies
    #     @cookies = {}
    #   end
    # end

  end
  
  before(:each) do
    Lacmus::Utils.restart_temp_user_ids
    Lacmus::SlotMachine.nuke_all_experiments
  end

  def create_and_activate_experiment
    experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description, {:screenshot_url => @experiment_screenshot_url})
    move_result = Lacmus::SlotMachine.move_experiment(experiment_id, :pending, :active)
    experiment_id
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


  def get_exposures_for_experiment(experiment_id, is_control = false)
    obj = Lacmus::Experiment.new(experiment_id)
    return obj.control_analytics[:exposures].to_i if is_control
    obj.experiment_analytics[:exposures].to_i
  end

  it "should increment exposure counters for an active exeriment" do
    experiment_id = create_and_activate_experiment
    all_exposures_1 = get_exposures_for_experiment(experiment_id) + get_exposures_for_experiment(experiment_id, true)
    expect(all_exposures_1).to eq(0)
    simple_experiment(experiment_id, "control", "experiment")

    expect(user_belongs_to_control_group?).to be_false
    expect(get_exposures_for_experiment(experiment_id, true)).to eq(0)
    expect(get_exposures_for_experiment(experiment_id)).to eq(1)
  end

  it "should not increment exposure counters for a pending or completed exeriment" do
    experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
    simple_experiment(experiment_id, "control", "experiment")
    pending_experiment_exposures = get_exposures_for_experiment(experiment_id) + get_exposures_for_experiment(experiment_id, true)
    expect(pending_experiment_exposures).to eq(0)

    Lacmus::SlotMachine.activate_experiment(experiment_id)
    simple_experiment(experiment_id, "control", "experiment")
    active_experiment_exposures = get_exposures_for_experiment(experiment_id) + get_exposures_for_experiment(experiment_id, true)
    expect(active_experiment_exposures).to eq(1)

    Lacmus::SlotMachine.deactivate_experiment(experiment_id)
    simple_experiment(experiment_id, "control", "experiment")
    completed_experiment_exposures = get_exposures_for_experiment(experiment_id) + get_exposures_for_experiment(experiment_id, true)
    expect(completed_experiment_exposures).to eq(1)

    # expect(Lacmus::Lab.user_belongs_to_control_group?).to be_false
    # expect(get_exposures_for_experiment(experiment_id, true)).to eq(0)
    # expect(get_exposures_for_experiment(experiment_id)).to eq(1)
  end

  it "should allow to update an experiment" do
    experiment_id = create_and_activate_experiment
    experiment = Lacmus::Experiment.new(experiment_id)
    expect(experiment.name).to eq(@experiment_name)
    expect(experiment.description).to eq(@experiment_description)
    expect(experiment.screenshot_url).to eq(@experiment_screenshot_url)

    experiment.name = "new name"
    experiment.description = "new description"
    experiment.screenshot_url = "new screenshot url"
    experiment.save

    loaded_experiment = Lacmus::Experiment.new(experiment_id)
    expect(loaded_experiment.name).to eq("new name")
    expect(loaded_experiment.description).to eq("new description")
    expect(loaded_experiment.screenshot_url).to eq("new screenshot url")
  end

  # it "should increment kpi value when marking kpi" do
  #   # experiment_id = create_and_activate_experiment
  #   # p experiment_id
  #   # p Lacmus::Experiment.key(experiment_id)
  #   # p Lacmus::Experiment.all_kpis_for_experiment(experiment_id)
  #   # p Lacmus::Experiment.all_keys_as_hash(experiment_id)
  #   # Lacmus::Experiment.mark_kpi!('ftb', experiment_id)
  #   # Lacmus::Experiment.mark_kpi!('ftg', experiment_id)
  #   # p Lacmus::Experiment.all_keys_as_hash(experiment_id)
  #   # p Lacmus::Experiment.all_kpis_for_experiment(experiment_id)
  # end

  # it "should not track user exposed to completed exeriment" do
  # 	# p helper.request.cookies[:awesome]
  # 	# Lacmus::Experiment.tuid_cookie
  # end

  # it "should not track exposed user twice" do
  # end

end