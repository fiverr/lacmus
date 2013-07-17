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
    Lacmus::SlotMachine.nuke_all_experiments
    Lacmus::Lab.clear_cookies
  end

  it "show render a changing group each time" do
    experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
    Lacmus::SlotMachine.activate_experiment(experiment_id)
    result = Lacmus::Lab.simple_experiment(experiment_id, "group_a", "experiment_group")
    puts "temp user id: #{Lacmus::Lab.cookies}"
    puts result
  end

  it "should not track user exposed to completed exeriment" do
  end

  it "should not track exposed user twice" do
  end

end