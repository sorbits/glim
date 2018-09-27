module GlimExtensions
  class MockFeedMetaTag < Liquid::Tag
    def initialize(tag_name, markup, options)
      super
    end

    def render(context)
      "<!-- Missing Feed Meta Tag -->"
    end
  end
end

Liquid::Template.register_tag("feed_meta", GlimExtensions::MockFeedMetaTag)
