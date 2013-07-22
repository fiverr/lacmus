require 'lacmus'

describe Lacmus::Experiment, "Experiment" do

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
  end

  def create_and_activate_experiment
    experiment_id = Lacmus::SlotMachine.create_experiment(@experiment_name, @experiment_description)
    move_result = Lacmus::SlotMachine.move_experiment(experiment_id, :pending, :active)
    experiment_id
  end

  it "should log experiment" do
  	tmp_user_id = rand(1000000)

  	experiment_id = create_and_activate_experiment
  	experiment_id2 = create_and_activate_experiment
  	exposed_at = Time.now
  	exposed_at2 = Time.now + 3600

    Lacmus::ExperimentHistory.log_experiment(tmp_user_id, experiment_id, exposed_at)
    exps = Lacmus::ExperimentHistory.experiments(tmp_user_id)
    exps
p exps
    # expect(Lacmus::ExperimentHistory.experiments(tmp_user_id))
# [['adas', 23412312.0]]
    Lacmus::ExperimentHistory.log_experiment(tmp_user_id, experiment_id2, exposed_at2)
    p Lacmus::ExperimentHistory.experiments(tmp_user_id)

    # expect(Lacmus::Lab.user_belongs_to_control_group?).to be_false
    # expect(get_exposures_for_experiment(experiment_id, true)).to eq(0)
    # expect(get_exposures_for_experiment(experiment_id)).to eq(1)
  end

end