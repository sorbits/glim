require_relative '../lib/exception'
require 'listen'
require 'mime/types'
require 'socket'
require 'webrick'
require 'websocket'

module WebSocket
  class Connection
    attr_reader :socket

    def self.establish(socket)
      handshake = WebSocket::Handshake::Server.new
      handshake << socket.gets until handshake.finished?

      raise "Malformed handshake received from WebSocket client" unless handshake.valid?

      socket.puts(handshake.to_s)
      Connection.new(socket, handshake)
    end

    def initialize(socket, handshake)
      @socket    = socket
      @handshake = handshake
    end

    def puts(message)
      frame = WebSocket::Frame::Outgoing::Server.new(version: @handshake.version, data: message, type: :text)
      @socket.puts(frame.to_s)
    end

    def each_message
      frame = WebSocket::Frame::Incoming::Server.new(version: @handshake.version)
      frame << @socket.read_nonblock(4096)
      while message = frame.next
        yield message
      end
    end
  end

  class Server
    def initialize(host: 'localhost', port: nil)
      @server, @rd_pipe, @wr_pipe = TCPServer.new(host, port), *IO.pipe
    end

    def broadcast(message)
      @wr_pipe.puts(message)
    end

    def shutdown
      broadcast('shutdown')

      @wr_pipe.close
      @wr_pipe = nil

      @thread.join

      @server.close
      @server = nil
    end

    def start
      @thread = Thread.new do
        connections = []
        running = true
        while running
          rs, _, _ = IO.select([ @server, @rd_pipe, *connections.map { |conn| conn.socket } ])
          rs.each do |socket|
            if socket == @server
              socket = @server.accept
              begin
                connections << Connection.establish(socket)
              rescue => e
                $log.warn("Failed to perform handshake with new WebSocket client: #{e}", e)
                socket.close
              end
            elsif socket == @rd_pipe
              message = @rd_pipe.gets.chomp
              if message == 'shutdown'
                running = false
                break
              end
              $log.debug("Send ‘#{message}’ to #{connections.count} WebSocket #{connections.count == 1 ? 'client' : 'clients'}") unless connections.empty?
              connections.each do |conn|
                begin
                  conn.puts(message)
                rescue => e
                  $log.warn("Error writing to WebSocket client socket: #{e}")
                end
              end
            else
              if conn = connections.find { |candidate| candidate.socket == socket }
                begin
                  conn.each_message do |frame|
                    $log.debug("Received #{frame.to_s.size} bytes from WebSocket client: #{frame}") unless frame.to_s.empty?
                  end
                rescue IO::WaitReadable
                  $log.warn("IO::WaitReadable exception while reading from WebSocket client")
                rescue EOFError
                  conn.socket.close
                  connections.delete(conn)
                end
              end
            end
          end
        end
        @rd_pipe.close
        @rd_pipe = nil
      end
    end
  end
end

module Glim
  module LocalServer
    class Servlet < WEBrick::HTTPServlet::AbstractServlet
      @@mutex = Mutex.new

      def initialize(server, config)
        @config = config
      end

      def do_GET(request, response)
        @@mutex.synchronize do
          do_GET_impl(request, response)
        end
      end

      def do_GET_impl(request, response)
        status, mime_type, body, file = 200, nil, nil, nil

        if request.path == '/.ws/script.js'
          mime_type, body = self.mime_type_for(request.path), self.websocket_script
        elsif page = self.find_page(request.path)
          file = page
        elsif dir = self.find_directory(request.path)
          if request.path.end_with?('/')
            if request.path == '/' || @config['show_dir_listing']
              mime_type, body = 'text/html', self.directory_index_for_path(dir)
            else
              $log.warn("Directory index forbidden for: #{request.path}")
              status = 403
            end
          else
            response['Location'] = "#{dir}/"
            status = 302
          end
        else
          $log.warn("No file for request: #{request.path}")
          status = 404
        end

        if status != 200 && body.nil? && file.nil?
          unless file = self.find_error_page(status, request.path)
            mime_type, body = 'text/html', self.error_page_for_status(status, request.path)
          end
        end

        mime_type ||= file ? self.mime_type_for(file.output_path('/')) : 'text/plain'
        body      ||= content_for_file(file)

        response['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response['Pragma']        = 'no-cache'
        response['Expires']       = '0'
        response.status           = status
        response.content_type     = mime_type
        response.body             = mime_type.start_with?('text/html') ? inject_reload_script(body) : body
      end

      def content_for_file(file)
        if file.frontmatter?
          begin
            file.output
          rescue Glim::Error => e
            content = "<pre>#{e.messages.join("\n")}</pre>"
            self.create_page("Error", "Exception raised for <code>#{file}</code>", content)
          rescue => e
            content = "<pre>#{e.to_s}</pre>"
            self.create_page("Error", "Exception raised for <code>#{file}</code>", content)
          end
        else
          File.read(file.path)
        end
      end

      def find_page(path)
        self.files.find do |file|
          candidate = file.output_path('/')
          if path == candidate || path + File.extname(candidate) == candidate
            true
          elsif path.end_with?('/')
            File.basename(candidate, '.*') == 'index' && path + File.basename(candidate) == candidate
          end
        end
      end

      def find_error_page(status, path)
        candidates = self.files.select do |file|
          file.basename == status.to_s && path_descends_from?(path, File.dirname(file.output_path('/')))
        end
        candidates.max { |lhs, rhs| lhs.output_path('/').size <=> rhs.output_path('/').size }
      end

      def find_directory(path)
        path = path.chomp('/') unless path == '/'
        self.files.map { |file| File.dirname(file.output_path('/')) }.find { |dir| path == dir }
      end

      def directory_index_for_path(path)
        candidates = self.files.map { |file| file.output_path('/') }
        candidates = candidates.select { |candidate| path_descends_from?(candidate, path) }
        candidates = candidates.map { |candidate| candidate.sub(/(^#{Regexp.escape(path.chomp('/'))}\/[^\/]+\/?).*/, '\1') }.sort.uniq
        candidates.unshift(path + '/..') if path != '/'

        heading = "Index of <code>#{path}</code>"
        content = candidates.map do |candidate|
          "<li><a href = '#{candidate}'>#{candidate.sub(/.*?([^\/]+\/?)$/, '\1')}</a></li>"
        end

        self.create_page("Directory Index", heading, "<ul>#{content.join("\n")}</ul>")
      end

      def error_page_for_status(status, path)
        case status
          when 302 then title, heading, content = "302 Redirecting…", "Redirecting…",    "Your browser should have redirected you."
          when 403 then title, heading, content = "403 Forbidden",    "Forbidden",       "You don't have permission to access <code>#{path}</code> on this server."
          when 404 then title, heading, content = "404 Not Found",    "Not Found",       "The requested URL <code>#{path}</code> was not found on this server."
          else          title, heading, content = "Error #{status}",  "Error #{status}", "No detailed description of this error."
        end
        self.create_page(title, heading, content)
      end

      def websocket_script
        <<~JS
        const glim = {
          connect: function (host, port, should_retry, should_reload) {
            const server = host + ":" + port
            console.log("Connecting to Glim’s live reload server (" + server + ")…");

            const socket = new WebSocket("ws://" + server + "/socket");

            socket.onopen = () => {
              console.log("Established connection: Live reload enabled.")
              if(should_reload) {
                document.location.reload(true);
              }
            };

            socket.onmessage = (event) => {
              console.log("Message from live reload server: " + event.data);

              if(event.data == 'reload') {
                document.location.reload(true);
              }
              else if(event.data == 'close') {
                window.close();
              }
            };

            socket.onclose = () => {
              console.log("Lost connection: Live reload disabled.")

              if(should_retry) {
                window.setTimeout(() => this.connect(host, port, should_retry, true), 2500);
              }
            };
          },
        };

        glim.connect('#{@config['host']}', #{@config['livereload_port']}, true /* should_retry */, false /* should_reload */);
        JS
      end

      def path_descends_from?(path, parent)
        parent == '/' || path[parent.chomp('/').size] == '/' && path.start_with?(parent)
      end

      def create_page(title, heading, content)
        <<~HTML
        <style>body {
          font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;
        }
        </style>
        <title>#{title}</title>
        <h1>#{heading}</h1>
        #{content}
        HTML
      end

      def inject_reload_script(content)
        return content unless @config['livereload']

        script_tag = "<script src='#{@config['url']}/.ws/script.js'></script>"
        if content =~ /<head.*?>/
          content = "#$`#$&#{script_tag}#$'"
        elsif content =~ /<html.*?>/
          content = "#$`#$&#{script_tag}#$'"
        else
          content = script_tag + content
        end
      end

      def files
        @config.site.files_and_documents.select { |file| file.write? }
      end

      def mime_type_for(filename, encoding = nil)
        if type = MIME::Types.type_for(filename).shift
          if type.ascii? || type.media_type == 'text' || %w( ecmascript javascript ).include?(type.sub_type)
            "#{type.content_type}; charset=#{encoding || @config['encoding']}"
          else
            type.content_type
          end
        else
          'application/octet-stream'
        end
      end
    end

    def self.start(config)
      config['url'] = "http://#{config['host']}:#{config['port']}"
      project_dir = config.site.project_dir

      websocket_server, listener = nil, nil

      if config['livereload']
        websocket_server = WebSocket::Server.new(host: config['host'], port: config['livereload_port'])
        websocket_server.start
      end

      server = WEBrick::HTTPServer.new(
        BindAddress: config['host'],
        Port:        config['port'],
        Logger:      WEBrick::Log.new('/dev/null'),
        AccessLog:   [],
      )

      server.mount('/', Servlet, config)

      if config['watch'] || config['livereload']
        listener = Listen.to(project_dir) do |modified, added, removed|
          paths = [ *modified, *added, *removed ]
          $log.debug("File changes detected for: #{paths.select { |path| path.start_with?(project_dir) }.map { |path| Util.relative_path(path, project_dir) }.join(', ')}")
          config.reload
          websocket_server.broadcast('reload') if websocket_server
        end
        $log.debug("Watching #{project_dir} for changes")
        listener.start
      end

      trap("INT") do
        server.shutdown
      end

      if config['open_url'] && File.executable?('/usr/bin/open')
        page = config.site.links['.']
        system('/usr/bin/open', page ? page.url : config['url'])
      end

      $log.info("Starting server on #{config['url']}")
      server.start
      $log.info("Server shutting down…")

      listener.stop if listener

      if websocket_server
        if config['open_url'] && File.executable?('/usr/bin/open')
          websocket_server.broadcast('close')
        end

        websocket_server.shutdown
      end
    end
  end
end
