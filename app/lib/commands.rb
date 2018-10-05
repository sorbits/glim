module Glim
  module Commands
    def self.build(config)
      output_dir = File.expand_path(config['destination'])
      files      = config.site.files_and_documents.select { |file| file.write? }
      symlinks   = (config.site.symlinks || []).map { |link| [ File.expand_path(File.join(link[:data]['domain'] || '.', link[:name]), output_dir), link[:realpath] ] }.to_h

      output_paths = files.map { |file| file.output_path(output_dir) }
      output_paths.concat(symlinks.keys)

      delete_files, delete_dirs = items_in_directory(output_dir, skip: config['keep_files'])
      deleted = delete_items(delete_files, delete_dirs, keep: output_paths)
      created, updated, warnings, errors = *generate(output_dir, config['jobs'] || 7, files, backtrace: config['show_backtrace'])

      symlinks.each do |dest, path|
        FileUtils.mkdir_p(File.dirname(dest))
        begin
          File.symlink(path, dest)
          created << dest
        rescue Errno::EEXIST
          if File.readlink(dest) != path
            File.unlink(dest)
            File.symlink(path, dest)
            updated << dest
          end
        end
      end

      [ [ 'Created', created ], [ 'Deleted', deleted ], [ 'Updated', updated ] ].each do |label, files|
        unless files.empty?
          STDERR.puts "==> #{label} #{files.size} #{files.size == 1 ? 'File' : 'Files'}"
          STDERR.puts files.map { |path| Util.relative_path(path, output_dir) }.sort.join(', ')
        end
      end

      unless warnings.empty?
        STDERR.puts "==> #{warnings.size} #{warnings.size == 1 ? 'Warning' : 'Warnings'}"
        warnings.each do |message|
          STDERR.puts message
        end
      end

      unless errors.empty?
        STDERR.puts "==> Stopped After #{errors.size} #{errors.size == 1 ? 'Error' : 'Errors'}"
        errors.each do |arr|
          arr.each_with_index do |err, i|
            STDERR.puts err.gsub(/^/, '  '*i)
          end
        end
      end
    end

    def self.clean(config)
      files, dirs = items_in_directory(File.expand_path(config['destination']), skip: config['keep_files'])

      if config['dry_run']
        if files.empty?
          STDOUT.puts "No files to delete"
        else
          files.each do |file|
            STDOUT.puts "Delete #{Util.relative_path(file, File.expand_path(config['source']))}"
          end
        end
      else
        deleted = delete_items(files, dirs)
        STDOUT.puts "Deleted #{deleted.size} #{deleted.size == 1 ? 'File' : 'Files'}."
      end
    end

    def self.profile(config)
      Profiler.enabled = true

      site = Profiler.run("Setting up site") do
        config.site
      end

      Profiler.run("Loading cache") do
        Glim::Cache.load
      end

      files = []

      Profiler.run("Loading pages") do
        files.concat(site.files)
      end

      Profiler.run("Loading collections") do
        files.concat(site.documents)
      end

      Profiler.run("Generating virtual pages") do
        files.concat(site.generated_files)
      end

      files = files.select { |file| file.frontmatter? }

      Profiler.run("Expanding liquid tags") do
        files.each { |file| file.content('post-liquid') }
      end

      Profiler.run("Transforming pages") do
        files.each { |file| file.content('pre-output') }
      end

      Profiler.run("Creating final output (layout)") do
        files.each { |file| file.output }
      end

      Profiler.enabled = false
    end

    # ===========
    # = Private =
    # ===========

    def self.items_in_directory(dir, skip: [])
      files, dirs = [], []

      begin
        Find.find(dir) do |path|
          next if path == dir
          Find.prune if skip.include?(File.basename(path))

          if File.file?(path) || File.symlink?(path)
            files << path
          elsif File.directory?(path)
            dirs << path
          else
            $log.warn("Unknown entry: #{path}")
          end
        end
      rescue Errno::ENOENT
      end

      [ files, dirs ]
    end

    private_class_method :items_in_directory

    def self.delete_items(files, dirs, keep: [])
      res = []

      keep_files = Set.new(keep)
      files.each do |path|
        unless keep_files.include?(path)
          begin
            File.unlink(path)
            res << path
          rescue => e
            $log.error("Error unlinking ‘#{path}’: #{e}\n")
          end
        end
      end

      dirs.sort.reverse.each do |path|
        begin
          Dir.rmdir(path)
        rescue Errno::ENOTEMPTY => e
          # Ignore
        rescue => e
          $log.error("Error removing directory ‘#{path}’: #{e}\n")
        end
      end

      res
    end

    private_class_method :delete_items

    def self.generate(output_dir, number_of_jobs, files, backtrace: false)
      Profiler.run("Creating pages") do
        if number_of_jobs == 1
          generate_subset(output_dir, files, backtrace: backtrace)
        else
          generate_async(output_dir, files.shuffle, number_of_jobs, backtrace: backtrace)
        end
      end
    end

    private_class_method :generate

    def self.generate_async(output_dir, files, number_of_jobs, backtrace: false)
      total  = files.size
      slices = number_of_jobs.times.map do |i|
        first = (total *    i  / number_of_jobs).ceil
        last  = (total * (i+1) / number_of_jobs).ceil
        files.shift(last-first)
      end

      Glim::Cache.track_updates = true
      semaphore = Mutex.new
      created, updated, warnings, errors = [], [], [], []

      threads = slices.each_with_index.map do |files_slice, i|
        pipe_rd, pipe_wr = IO.pipe
        pid = fork do
          start = Time.now
          pipe_rd.close
          created, updated, warnings, errors = *generate_subset(output_dir, files_slice, backtrace: backtrace)
          pipe_wr << Marshal.dump({
            'cache_updates' => Glim::Cache.updates,
            'created'       => created,
            'updated'       => updated,
            'warnings'      => warnings,
            'errors'        => errors,
            'duration'      => Time.now - start,
            'id'            => i,
          })
          pipe_wr.close
        end

        Process.detach(pid)

        Thread.new do
          pipe_wr.close
          res = Marshal.load(pipe_rd)
          semaphore.synchronize do
            Glim::Cache.merge!(res['cache_updates'])
            created  += res['created']
            updated  += res['updated']
            warnings += res['warnings']
            errors   += res['errors']
            $log.debug("Wrote #{files_slice.size} pages in #{res['duration']} seconds (thread #{res['id']})") if Profiler.enabled
          end
        end
      end

      threads.each { |thread| thread.join }

      [ created, updated, warnings, errors ]
    end

    private_class_method :generate_async

    def self.generate_subset(output_dir, files, backtrace: false)
      created, updated, warnings, errors = [], [], [], []

      for file in files do
        dest = file.output_path(output_dir)
        file_exists = File.exists?(dest)

        FileUtils.mkdir_p(File.dirname(dest))
        if file.frontmatter?
          begin
            if !file_exists || File.read(dest) != file.output
              File.unlink(dest) if file_exists
              File.write(dest, file.output)
              (file_exists ? updated : created) << dest
            end
            warnings.concat(file.warnings.map { |warning| "#{file}: #{warning}" }) unless file.warnings.nil?
          rescue Glim::Error => e
            errors << [ "Unable to create output for: #{file}", *e.messages ]
            break
          rescue => e
            error = [ "Unable to create output for: #{file}", e.to_s ]
            error << e.backtrace.join("\n") if backtrace
            errors << error
            break
          end
        else
          unless File.file?(dest) && File.file?(file.path) && File.stat(dest).ino == File.stat(file.path).ino
            File.unlink(dest) if file_exists
            File.link(file.path, dest)
          end
        end
      end

      [ created, updated, warnings, errors ]
    end

    private_class_method :generate_subset
  end
end
