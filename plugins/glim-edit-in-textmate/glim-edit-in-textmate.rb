require 'cgi'

module GlimExtensions
  class EditInTextMate < Glim::Filter
    transforms 'output.html' => 'output.html'

    def initialize(site)
      @enabled = site.config['environment'] == 'development'
    end

    def transform(content, page, options)
      if @enabled && page.path
        script_tag = edit_in_textmate_script(page.path)
        if content =~ /<head.*?>/
          content = "#$`#$&#{script_tag}#$'"
        elsif content =~ /<html.*?>/
          content = "#$`#$&#{script_tag}#$'"
        else
          content = script_tag + content
        end
      end
      content
    end

    def edit_in_textmate_script(path)
      <<~HTML
      <script>
      window.onkeydown = function (e) {
        if(!document.activeElement || document.activeElement == document.body) {
          if(e.key == 'e' && !(e.altKey || e.shiftKey || e.ctrlKey || e.metaKey)) {
            window.location = "txmt://open?url=#{CGI.escape('file://' + path)}";
          }
        }
      };
      </script>
      HTML
    end
  end
end
