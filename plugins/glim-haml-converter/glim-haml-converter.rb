require 'haml'

module GlimHAMLSupport
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

  class HAMLToHTML < Glim::Filter
    transforms 'haml' => 'html'

    def initialize(site)
      @site = site
    end

    def transform(content, page, options)
      engine  = Haml::Engine.new(content)
      content = engine.render(ExposeLiquidFilters.new(@site, page), :content => content, :page => ExposeLiquidGetterAPI.new(page), :site => ExposeLiquidGetterAPI.new(@site))
    end
  end

  class HAMLLayout < Glim::Filter
    transforms '*' => 'output'

    def initialize(site)
      @site  = site
      @cache = {}
    end

    def find_layout(name)
      unless name.nil? || @cache.has_key?(name)
        path = File.join(@site.layouts_dir, name + '.haml')
        @cache[name] = if File.exists?(path)
          Glim::FileItem.new(@site, path)
        end
      end
      @cache[name]
    end

    def transform(content, page, options)
      layout = page.data['layout']
      if find_layout(layout)
        while layout_file = find_layout(layout)
          engine  = Haml::Engine.new(layout_file.content('liquid'))
          content = engine.render(ExposeLiquidFilters.new(@site, page), :content => content, :page => ExposeLiquidGetterAPI.new(page), :site => ExposeLiquidGetterAPI.new(@site))
          layout  = layout_file.data['layout']
        end
        content
      else
        super
      end
    end
  end
end
