Gem::Specification.new do |spec|
  spec.name        = "data_builder"
  spec.version     = "1.0.0"
  spec.authors     = [ "Digital Commons Cooperative" ]
  spec.summary     = "MykoMap dataset builder engine"
  spec.description = "Public wizard turning a CSV or open-data source into a downloadable MykoMap dataset zip."
  spec.files       = Dir["{app,config,lib}/**/*"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "rails", ">= 8.1"
  spec.add_dependency "rubyzip"
end
