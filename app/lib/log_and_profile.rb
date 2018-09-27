require 'logger'

$log = Logger.new(STDERR)
$log.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S.%3N')}] [#{Process.pid}] %7s #{msg}\n" % "[#{severity}]"
end

class Profiler
  @@instance = nil

  def initialize(format = "Program ran in %.3f seconds")
    @current = Entry.new(format)
  end

  def self.enabled=(flag)
    @@instance.dump if @@instance
    @@instance = flag ? Profiler.new : nil
  end

  def self.enabled
    @@instance ? true : false
  end

  def self.run(action, &block)
    if @@instance
      @@instance.profile("#{action} took %.3f seconds", &block)
    else
      block.call
    end
  end

  def self.group(group, &block)
    if @@instance
      @@instance.profile_group(group, &block)
    else
      block.call
    end
  end

  def profile(format)
    parent = @current
    parent.add_child(@current = Entry.new(format))
    res = yield
    @current.finished!
    @current = parent
    res
  end

  def profile_group(group)
    @current.group(group) do
      yield
    end
  end

  def dump
    @current.dump
  end

  class Entry
    attr_reader :duration

    def initialize(format)
      @format = format
      @start  = Time.now
    end

    def group(name)
      @groups ||= {}
      @groups[name] ||= { :duration => 0, :count => 0 }

      previous_group, @current_group = @current_group, name

      start = Time.now
      res = yield
      @groups[name][:duration] += Time.now - start
      @groups[name][:count] += 1

      @groups[previous_group][:duration] -= Time.now - start if previous_group
      @current_group = previous_group

      res
    end

    def add_child(child)
      @children ||= []
      @children << child
    end

    def finished!
      @duration ||= Time.now - @start
    end

    def indent(level)
      '  ' * level
    end

    def dump(level = 0)
      self.finished!

      STDERR.puts indent(level) + (@format % @duration)

      if @groups
        @groups.sort_by { |group, info| info[:duration] }.reverse.each do |group, info|
          STDERR.puts indent(level+1) + "[#{group}: %.3f seconds, called #{info[:count]} time(s), %.3f seconds/time]" % [ info[:duration], info[:duration] / info[:count] ]
        end
      end

      if @children
        @children.sort_by { |child| child.duration }.reverse.each do |child|
          child.dump(level + 1)
        end
      end
    end
  end
end
