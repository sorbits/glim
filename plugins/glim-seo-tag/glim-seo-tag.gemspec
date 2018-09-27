Gem::Specification.new do |spec|
  spec.name          = File.basename(Dir.pwd)
  spec.version       = '0.1.1'
  spec.author        = 'Allan Odgaard'
  spec.summary       = 'A mock for jekyll-seo-tag.'
  spec.homepage      = 'https://macromates.com/glim/'
  spec.license       = 'MIT'

  spec.files         = Dir.glob('*.rb')
  spec.require_paths = ['.']
end
