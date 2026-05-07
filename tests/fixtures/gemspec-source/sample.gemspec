Gem::Specification.new do |s|
  s.name        = 'sample'
  s.version     = '0.1.0'
  s.summary     = 'Fixture for postcut gemspec parsing'
  s.authors     = ['fixture']

  s.add_runtime_dependency 'addressable', '~> 2.8'
  s.add_runtime_dependency 'json', '>= 2.0'
  s.add_dependency 'rake'

  s.add_development_dependency 'rspec', '~> 3.13'
  s.add_development_dependency('minitest', '~> 6.0')
end
