# encoding: utf-8
require 'redis'
require 'yaml'

require 'active_support/concern'
require 'active_support/core_ext/hash/indifferent_access'

require 'lacmus/version'
require 'lacmus/settings'
require 'lacmus/lab'
require 'lacmus/async_lab'
require 'lacmus/slot_machine'
require 'lacmus/alternative_user'
require 'lacmus/experiment'
require 'lacmus/experiment_history'

# When running under rails, include Lacmus::Lab in ActionController::Base.
# This will initialize Lacmus and make it available under all controllers,
# views and helpers.
if Lacmus::Settings.running_under_rails?
  ActionController::Base.send(:include, Lacmus::Lab)
end

module Lacmus
  extend self

  # Prefix used for the different redis keys.
  LACMUS_PREFIX = "lcms-#{Settings.env_name}"

  # Store the database connection (redis).
  @@fast_engine = nil

  # Return the redis connection, acts as the Lacmus' engine.
  #
  # @return [ Redis ] The redis connection.
  #
  def fast_storage
    @@fast_engine ||= Redis.new(Settings.fast_storage)
  end

  # Generate a new unique user id for the given user.
  # The counter will reset itself when it reaches 10M.
  #
  # @return [ Integer ] The new user id
  #
  def generate_user_id
    new_user_id = fast_storage.incr user_id_key
    if new_user_id > 100000000
      fast_storage.set(user_id_key, 1)
    end
    new_user_id
  end

  def restart_user_ids_counter
    fast_storage.del user_id_key
  end

  def user_id_key
    "#{LACMUS_PREFIX}-tmp-uid"
  end
end