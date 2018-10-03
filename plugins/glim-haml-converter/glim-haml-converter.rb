require 'haml'

module GlimExtensions
  class ExposeLiquidFilters
    def initialize(site, page)
      @context = Liquid::Context.new({ 'site' => site, 'page' => page })
    end

    def method_missing(method, *args)
      @context.strainer.invoke(method, *args)
    end
  end

  class ExposeLiquidGetterAPI
    def initialize(obj)
      @obj = obj.to_liquid
    end

    def method_missing(method, *args)
      @obj.liquid_method_missing(method.to_s)
    end
  end

  class HTMLAbstractionMarkupLanguage < Glim::Filter
    transforms 'haml' => 'html'

    def initialize(site)
      @site = site
    end

    def transform(content, page, options)
      engine  = Haml::Engine.new(content)
      content = engine.render(ExposeLiquidFilters.new(@site, page), :content => content, :page => ExposeLiquidGetterAPI.new(page), :site => ExposeLiquidGetterAPI.new(@site))
    end
  end
end
