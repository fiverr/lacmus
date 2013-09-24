# Require pry, allowing the usage of binding.pry
# when debugging tests.
require 'pry'

# Set the Lacmus root and env constants, used to load
# the correct yml file for test env.
Lacmus::ROOT = "#{Dir.pwd}/spec"
Lacmus::ENV  = "test"

# Set the cache interval to zero, which means we won't cache
# experiment slots on test env (all calls will pull it from redis).
$__lcms__worker_cache_interval = 0

# Constants used to mock and test experiments.
EXPERIMENT_NAME = "experimentum"
EXPERIMENT_DESCRIPTION = "dekaprius dela karma"
EXPERIMENT_SCREENSHOT_URL = "http://google.com"

# ----------------------------------------------------------------
# HELPER METHODS
# ----------------------------------------------------------------

  def create_experiment
    attrs = {
      :name           => EXPERIMENT_NAME,
      :description    => EXPERIMENT_DESCRIPTION,
      :screenshot_url => EXPERIMENT_SCREENSHOT_URL
    }
    Lacmus::Experiment.create!(attrs)
  end

  def create_and_activate_experiment
    exp_obj = create_experiment
    exp_obj.activate!
    exp_obj
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

  def clear_cookies_and_uid_hash
    clear_cookies
    @uid_hash = {}
  end

  def reset_instance_variables
    @uid_hash = nil
    @user_experiment = nil
    @rendered_control_group = nil
    reset_active_experiments_cache
  end

  def simulate_unique_visitor_exposure(experiment_id)
    clear_cookies_and_uid_hash
    simple_experiment(experiment_id, "control", "experiment")
  end

# ----------------------------------------------------------------