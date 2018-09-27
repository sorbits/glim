require 'fileutils'

module Glim
  class Cache
    CACHE_PATH = '.cache/glim/data.bin'

    class << self
      def load
        cache
      end

      def save
        unless @cache.nil?
          FileUtils.mkdir_p(File.dirname(CACHE_PATH))
          open(CACHE_PATH, 'w') do |io|
            Marshal.dump(cache, io)
          end
        end
      end

      def track_updates=(flag)
        @updates = flag ? {} : nil
      end

      def updates
        @updates
      end

      def merge!(updates)
        updates.each do |group, paths|
          (cache[group] ||= {}).merge!(paths)
        end
      end

      def getset(path, group = :default)
        begin
          mtime = File.stat(path).mtime
          if record = cache.dig(group, path)
            if mtime == record['modified']
              return record['data']
            end
          end

          record = {
            'modified' => mtime,
            'data'     => yield,
          }

          (cache[group] ||= {})[path] = record
          (@updates[group] ||= {})[path] = record if @updates

          record['data']
        rescue Errno::ENOENT
          $log.warn("File does not exist: #{path}")
          nil
        end
      end

      private

      def cache
        @cache ||= open(CACHE_PATH) { |io| Marshal.load(io) } rescue {}
      end
    end
  end
end
