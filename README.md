# Glim — Static Site Generator

Glim is a static site generator which is semi-compatible with Jekyll but faster and with some additional features:

* Running `serve` will generate content as requested by the browser (lazy evaluation), this allows instant previews as the full site doesn’t have to be built first. It also means that if there is a (syntax) error generating a page, the error will be shown in your browser and the error page even supports automatic reload. Another advantage of this approach is that during testing we do not write anything to disk, so `_site` will always contain deployment-ready pages (no instances of `localhost:4000`, injected reload scripts, or unpublished drafts).

* Running `build` will make use of multiple tasks to parallelize content generation.

* Collections have been generalized so that they all support both tags, categories, drafts, and arbitrary sorting (e.g. reverse chronological). There is nothing special about `_posts`.

* Support for multiple domains has been added. This means generating content for `example.org` and `blog.example.org` can be done using the same project, so that resources can be shared and cross-linking is possible via the `link` tag.

* Extensible render pipeline: Content is transformed using a pipeline where it is trivial to add new filters, this allows adding new converters, override the default converters, or simply pre/post-process content to support custom syntax, inject content, run the generated HTML through a validator, or similar.

* Introduced a `digest` variable which can be used in permalinks to ensure that a page’s URL will change when the content is updated (guaranteed cache invalidation useful for CSS and JavaScript).

* Easy pagination of both collections and data structures.

* Collections can have pages generated for tags and categories. Making this a built-in feature makes it possible to iterate generated pages and link to these using their `url` property rather than make assumptions about where such pages end up in the file hierarchy.

* Any change to a site file, be it files under `_data` or even `_config.yml`, will trigger a browser reload that will fetch the updated page. This is possible because we use lazy evaluation, so a file system change is effectively just triggering a cache flush, rather than having to rebuild the entire site.

* Default values for pages can be set using file globs, making it easy to use the same set of values for a broad set of files, and default values for collection files can be set under the respective collection, which is extra useful when using cascading configuration files.

* Introduced a `source_dir` setting to allow putting site content in a subdirectory, obviating the need for maintaining a list of excludes and/or prefixing non-publishable items with underscores.

## Installing

Glim can be installed via `rubygems`:

    gem install glim

## Documentation

Familiarity with Jekyll is assumed. The features that Glim adds are documented in the [Glim Manual](https://macromates.com/glim/).
