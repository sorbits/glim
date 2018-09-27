module GlimExtensions
  class MockSEOTag < Liquid::Tag
    def initialize(tag_name, markup, options)
      super
    end

    def render(context)
      "<!-- Missing SEO Tag -->"
    end
  end
end

Liquid::Template.register_tag("seo", GlimExtensions::MockSEOTag)
