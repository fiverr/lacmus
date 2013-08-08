# Require pry, allowing the usage of binding.pry
# when debugging failed tests
require 'pry'

# Set the Lacmus root and env constants, used to load
# the correct yml file for test env.
Lacmus::ROOT = "#{Dir.pwd}/spec"
Lacmus::ENV  = "test"

# Set the cache interval to zero, which means we won't cache
# experiment slots on test env (all calls will pull it from redis)
$__lcms__worker_cache_interval = 0