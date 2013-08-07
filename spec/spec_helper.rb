# Require pry, allowing the usage of binding.pry
# when debugging failed tests
require 'pry'

# Set the Lacmus root and env constants, used to load
# the correct yml file for test env.
Lacmus::ROOT = "#{Dir.pwd}/spec"
Lacmus::ENV  = "test"