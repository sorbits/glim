module Jekyll
  def self.sanitized_path(path, dir)
    File.expand_path(path, dir)
  end
end

module GlimExtensions
  class Sass < Glim::Filter
    transforms 'scss' => 'css', 'sass' => 'css'

    @@did_require_sass_converter = false

    def initialize(site)
      unless @@did_require_sass_converter
        @@did_require_sass_converter = true
        begin
          require 'jekyll-sass-converter'
        rescue LoadError => e
          STDERR << "Error loading ‘jekyll-sass-converter’: #{e}\n"
        end
      end

      @converters ||= Jekyll::Plugin.plugins_of_type(Jekyll::Converter).sort.map { |klass| klass.new(site.config) }
    end

    def transform(content, page, options)
      if converter = @converters.find { |c| c.matches(page.extname) }
        content = converter.convert(content)
      end
      content
    end
  end
end
