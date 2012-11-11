# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "siriproxy-squeezenet"
  s.version     = "0.1.0" 
  s.authors     = ["Joep Verhaeg"]
  s.email       = ["info@joepverhaeg.nl"]
  s.homepage    = "http://www.joepverhaeg.nl"
  s.summary     = %q{SqueezeNet Siri Proxy Plugin}
  s.description = %q{Custom plugin to control my Squeezebox and add Spotify music with Siri. }

  s.rubyforge_project = "siriproxy-squeezenet"

  s.files         = `git ls-files 2> /dev/null`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/* 2> /dev/null`.split("\n")
  s.executables   = `git ls-files -- bin/* 2> /dev/null`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  # s.add_runtime_dependency "rest-client"
end
