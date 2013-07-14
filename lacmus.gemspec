# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'lacmus/version'

Gem::Specification.new do |spec|
  spec.name          = "lacmus"
  spec.version       = Lacmus::VERSION
  spec.authors       = ["Shai Wininger", "Moshe Lieberman"]
  spec.email         = ["lacmus@fiverr.com"]
  spec.description   = "An a/b testing framework"
  spec.summary       = ""
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
