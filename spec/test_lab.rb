require 'lacmus'


describe Lacmus::Lab, "Lab" do

	before(:all) do
  
    @experiment_name = "experimentum"
    @experiment_description = "dekaprius dela karma"

    # Object.define_method("cookies=") do |value|
    #   class_variable_set( "@cookies" , value )
    # end
    # Lacmus::Lab.class_variable_set(:@@cookies, {})

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

  it "different users should get different slots" do
    create_and_activate_experiment
    first_user_slot = Lacmus::Lab.slot_for_user
    Lacmus::Lab.clear_cookies
    second_user_slot = Lacmus::Lab.slot_for_user
    Lacmus::Lab.clear_cookies
    third_user_slot = Lacmus::Lab.slot_for_user
    
    expect(first_user_slot).not_to eq(second_user_slot)
    expect(third_user_slot).to eq(first_user_slot)
  end

  it "should render different results for control and experiment groups" do
    experiment_id = create_and_activate_experiment
    puts Lacmus::Lab.current_temp_user_id
    result1 = Lacmus::Lab.simple_experiment(experiment_id, "control", "experiment")
    expect(Lacmus::Lab.user_belongs_to_control_group?).to be_false
    expect(result1).to eq("experiment")
    Lacmus::Lab.clear_cookies
    puts Lacmus::Lab.current_temp_user_id
    result2 = Lacmus::Lab.simple_experiment(experiment_id, "control", "experiment")
    expect(Lacmus::Lab.user_belongs_to_control_group?).to be_true
    expect(result2).to eq("control")
  end

  it "should not track exposed user twice" do
    
  end

end










