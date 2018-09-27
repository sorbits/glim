require 'haml'

module GlimExtensions
  class HTMLAbstractionMarkupLanguage < Glim::Filter
    transforms 'haml' => 'html'

    def transform(content, page, options)
      engine = Haml::Engine.new(content)
      engine.render
    end
  end
end
