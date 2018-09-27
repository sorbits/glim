require_relative 'lib/version'

Gem::Specification.new do |spec|
  spec.name        = 'glim'
  spec.version     = Glim::VERSION
  spec.author      = 'Allan Odgaard'
  spec.summary     = 'Static site generator inspired by Jekyll but a lot faster'
  spec.description = 'Generating output is done in parallel using multiple tasks and lazy evaluation is used when serving pages locally for instant reloads when source content changes.'

  spec.license     = 'MIT'
  spec.homepage    = 'https://sigpipe.macromates.com/2018/creating-a-faster-jekyll/'

  spec.metadata = {
    'homepage_uri'      => 'https://sigpipe.macromates.com/2018/creating-a-faster-jekyll/',
    'documentation_uri' => 'https://macromates.com/glim/',
    'source_code_uri'   => 'https://github.com/sorbits/glim/',
    'mailing_list_uri'  => 'https://lists.macromates.com/listinfo/glim',
  }

  spec.bindir      = 'bin'
  spec.executables << 'glim'

  spec.files       = Dir.glob('{bin/*,lib/*.rb}')

  spec.required_ruby_version = ">= 2.3.0"

  spec.add_runtime_dependency 'mercenary', '~> 0.3'
  spec.add_runtime_dependency 'liquid', '~> 4.0'
  spec.add_runtime_dependency 'kramdown', '~> 1.14'
  spec.add_runtime_dependency 'listen', '~> 3.0'
  spec.add_runtime_dependency 'websocket', '~> 1.2'
  spec.add_runtime_dependency 'mime-types', '~> 3.2'
  spec.add_runtime_dependency 'glim-sass-converter', '~> 0.1'
  spec.add_runtime_dependency 'glim-seo-tag', '~> 0.1'
  spec.add_runtime_dependency 'glim-feed', '~> 0.1'
end
