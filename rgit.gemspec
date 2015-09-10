# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rgit/version'

Gem::Specification.new do |spec|
  spec.name          = "rgit"
  spec.version       = Rgit::VERSION
  spec.authors       = ["Ryan Benmalek"]
  spec.email         = ["ryanai3@hotmail.com"]

  spec.summary       = %q{Manage recursive git & push to submodules}
  spec.description   = %q{Exactly what it says }
  spec.homepage      = "TODO: Put your gem's website or public repo URL here."
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "NONE'"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "bin"
  spec.executables   = ["rgit"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor"
  spec.add_dependency "rugged"
  spec.add_dependency "parseconfig"
  spec.add_dependency "byebug"

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"
end
