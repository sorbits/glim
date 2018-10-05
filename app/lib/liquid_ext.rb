require 'kramdown'
require 'liquid'

module Glim
  module LiquidFilters
    def markdownify(input)
      return if input.nil?
      
      Profiler.group('markdownify') do
        if defined?(MultiMarkdown)
          MultiMarkdown.new("\n" + input, 'snippet', 'no_metadata').to_html
        else
          options  = @context['site']['kramdown'].map { |key, value| [ key.to_sym, value ] }.to_h
          document = Kramdown::Document.new(input, options)
          @context['warnings'].concat(document.warnings) if options[:show_warnings] && @context['warnings']
          document.to_html
        end
      end
    end

    def slugify(input)
      Util.slugify(input) unless input.nil?
    end

    def xml_escape(input)
      input.encode(:xml => :attr).gsub(/\A"|"\z/, '') unless input.nil?
    end

    def cgi_escape(input)
      CGI.escape(input) unless input.nil?
    end

    def absolute_url(path)
      return if path.nil?
      
      site, page = URI(@context['site']['url']), URI(@context['page']['url'])
      host, port = @context['site']['host'], @context['site']['port']
      
      if page.relative? || (site.host == host && site.port == port)
        site.merge(URI(path)).to_s
      else
        page.merge(URI(path)).to_s
      end
    end

    def relative_url(other)
      return if other.nil?
      
      site, page = URI(@context['site']['url']), URI(@context['page']['url'])
      host, port = @context['site']['host'], @context['site']['port']
      
      helper = lambda do |base, other|
        base_url, other_url = URI(base), URI(other)
        if other_url.absolute? && base_url.host == other_url.host
          other_url.path
        else
          other
        end
      end
      
      if page.relative? || (site.host == host && site.port == port)
        helper.call(@context['site']['url'], other)
      else
        helper.call(@context['page']['url'], other)
      end
    end

    def path_to_url(input)
      return if input.nil?
      
      if file = Jekyll.sites.last.links[input]
        file.url
      else
        raise Glim::Error.new("path_to_url: No file found for: #{input}")
      end
    end

    def date_to_xmlschema(input)
      Liquid::Utils.to_date(input).localtime.xmlschema unless input.nil?
    end

    def date_to_rfc822(input)
      Liquid::Utils.to_date(input).localtime.rfc822 unless input.nil?
    end

    def date_to_string(input)
      Liquid::Utils.to_date(input).localtime.strftime("%d %b %Y") unless input.nil?
    end

    def date_to_long_string(input)
      Liquid::Utils.to_date(input).localtime.strftime("%d %B %Y") unless input.nil?
    end

    def where(input, property, value)
      if input.respond_to?(:select) && property && value
        input = input.values if input.is_a?(Hash)
        input.select { |item| get_property(item, property) == value }
      else
        input
      end
    end

    def group_by(input, property)
      if input.respond_to?(:group_by) && property
        groups = input.group_by { |item| get_property(item, property) }
        groups.map { |key, value| { "name" => key, "items" => value, "size" => value.size } }
      else
        input
      end
    end

    def group_by_exp(input, variable, expression)
      return input unless input.respond_to?(:group_by)
      
      parsed_expr = Liquid::Variable.new(expression, Liquid::ParseContext.new)
      @context.stack do
        groups = input.group_by do |item|
          @context[variable] = item
          parsed_expr.render(@context)
        end
        groups.map { |key, value| { "name" => key, "items" => value, "size" => value.size } }
      end
    end

    private

    def get_property(obj, property)
      if obj.respond_to?(:to_liquid)
        property.to_s.split('.').reduce(obj.to_liquid) do |mem, key|
          mem[key]
        end
      elsif obj.respond_to?(:data)
        obj.data[property.to_s]
      else
        obj[property.to_s]
      end
    end
  end

  module LiquidTags
    class PostURL < Liquid::Tag
      def initialize(tag_name, markup, options)
        super
        @post_name = markup.strip
      end

      def render(context)
        if file = Jekyll.sites.last.post_links[@post_name]
          file.url
        else
          raise Glim::Error.new("post_url: No post found for: #{@post_name}")
        end
      end
    end

    class Link < Liquid::Tag
      def initialize(tag_name, markup, options)
        super
        @relative_path = markup.strip
      end

      def render(context)
        if file = Jekyll.sites.last.links[@relative_path]
          file.url
        else
          raise Glim::Error.new("link: No file found for: #{@relative_path}")
        end
      end
    end

    class HighlightBlock < Liquid::Block
      def initialize(tag_name, markup, tokens)
        super

        if markup =~ /^([a-zA-Z0-9.+#_-]+)((\s+\w+(=(\w+|"[^"]*"))?)*)\s*$/
          @language, @options = $1, $2.scan(/(\w+)(?:=(?:(\w+)|"([^"]*)"))?/).map do |key, value, list|
            [ key.to_sym, list ? list.split : (value || true) ]
          end.to_h
        else
          @language, @options = nil, {}
          $log.error("Unable to parse highlight tag: #{markup}") unless markup.strip.empty?
        end

        begin
          require 'rouge'
        rescue LoadError => e
          $log.warn("Unable to load the rouge gem required by the highlight tag: #{e}")
        end
      end

      def render(context)
        source = super.to_s.gsub(/\A[\r\n]+|[\r\n]+\z/, '')

        if defined?(Rouge)
          rouge_options = {
            :line_numbers => @options[:linenos] == true ? 'inline' : @options[:linenos],
            :wrap         => false,
            :css_class    => 'highlight',
            :gutter_class => 'gutter',
            :code_class   => 'code'
          }.merge(@options)

          lexer     = Rouge::Lexer.find_fancy(@language, source) || Rouge::Lexers::PlainText
          formatter = Rouge::Formatters::HTMLLegacy.new(rouge_options)
          source    = formatter.format(lexer.lex(source))

          $log.warn("No language specified in highlight tag. Will use #{lexer.class.name} to parse the code.") if @language.nil?
        end

        code_attributes = @language ? " class=\"language-#{@language.tr('+', '-')}\" data-lang=\"#{@language}\"" : ""
        "<figure class=\"highlight\"><pre><code#{code_attributes}>#{source.chomp}</code></pre></figure>"
      end
    end
  end

  def self.preprocess_template(source)
    source = source.gsub(/({%-? include )([\w.\/-]+)(.*?)(-?%})/) do
      prefix, include, variables, suffix = $1, $2, $3, $4
      unless variables.strip.empty?
        variables = ', ' + variables.scan(/(\w+)=(.*?)(?=\s)/).map { |key, value| "include_#{key}: #{value}" }.join(', ') + ' '
      end

      "#{prefix}\"#{include}\"#{variables}#{suffix}"
    end

    source.gsub!(/({{-? include)\.(.*?}})/) { "#$1_#$2" }
    source.gsub!(/({%-? .+? include)\.(.*?%})/) { "#$1_#$2" }

    source
  end

  class LocalFileSystem
    def initialize(*paths)
      @paths = paths.reject { |path| path.nil? }
    end

    def read_template_file(name)
      @cache ||= {}
      unless @cache[name]
        paths = @paths.map { |path| File.join(path, name) }
        if file = paths.find { |path| File.exist?(path) }
          @cache[name] = Glim.preprocess_template(File.read(file))
        end
      end
      @cache[name]
    end
  end
end

Liquid::Template.register_filter(Glim::LiquidFilters)
Liquid::Template.register_tag('post_url', Glim::LiquidTags::PostURL)
Liquid::Template.register_tag('link', Glim::LiquidTags::Link)
Liquid::Template.register_tag("highlight", Glim::LiquidTags::HighlightBlock)
