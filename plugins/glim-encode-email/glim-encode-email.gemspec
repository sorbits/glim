Gem::Specification.new do |spec|
  spec.name          = File.basename(Dir.pwd)
  spec.version       = '0.1'
  spec.author        = 'Allan Odgaard'
  spec.summary       = 'Encode email addresses using HTML entities.'
  spec.homepage      = 'https://macromates.com/glim/'
  spec.license       = 'MIT'

  spec.files         = Dir.glob('*.rb')
  spec.require_paths = ['.']

  spec.add_runtime_dependency 'glim', '~> 0.1'
end
