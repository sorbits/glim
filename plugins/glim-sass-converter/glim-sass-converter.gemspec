Gem::Specification.new do |spec|
  spec.name          = File.basename(Dir.pwd)
  spec.version       = '0.1'
  spec.author        = 'Allan Odgaard'
  spec.summary       = 'Wrapper for jekyll-sass-converter.'
  spec.homepage      = 'https://macromates.com/glim/'
  spec.license       = 'MIT'

  spec.files         = Dir.glob('*.rb')
  spec.require_paths = ['.']

  spec.add_runtime_dependency 'jekyll', '~> 3.8'
  spec.add_runtime_dependency 'jekyll-sass-converter', '~> 1.0'
end
