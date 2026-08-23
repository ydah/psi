# frozen_string_literal: true

require_relative "psi/version"
require_relative "psi/reading"
require_relative "psi/sampler"

# Reads Linux Pressure Stall Information (PSI).
module PSI
  RESOURCES = %i[cpu memory io irq].freeze

  class Error < StandardError; end
  class UnsupportedError < Error; end
  class TriggerError < Error; end

  class << self
    attr_writer :procfs_root

    def procfs_root
      @procfs_root ||= "/proc"
    end

    def supported?
      File.directory?(File.join(procfs_root, "pressure"))
    end

    def resources
      RESOURCES.select { |resource| File.file?(path_for(resource)) }
    end

    def read(resource, cgroup: nil)
      resource = validate_resource(resource)
      Reading.parse(resource, File.read(path_for(resource, cgroup: cgroup)))
    rescue Errno::ENOENT, Errno::EOPNOTSUPP => e
      raise UnsupportedError, e.message
    end

    def read_all(cgroup: nil)
      available = cgroup ? RESOURCES.select { |resource| File.file?(path_for(resource, cgroup: cgroup)) } : resources
      available.to_h { |resource| [resource, read(resource, cgroup: cgroup)] }
    end

    def current_cgroup
      entry = File.foreach(File.join(procfs_root, "self/cgroup")).find { |line| line.start_with?("0::") }
      raise UnsupportedError, "cgroup v2 is not mounted" unless entry

      File.join("/sys/fs/cgroup", entry.split("::", 2).last.strip.delete_prefix("/"))
    rescue Errno::ENOENT => e
      raise UnsupportedError, e.message
    end

    def path_for(resource, cgroup: nil)
      resource = validate_resource(resource)
      return File.join(cgroup, "#{resource}.pressure") if cgroup

      File.join(procfs_root, "pressure", resource.to_s)
    end

    private

    def validate_resource(resource)
      resource = resource.to_sym if resource.respond_to?(:to_sym)
      raise ArgumentError, "unknown resource: #{resource.inspect}" unless RESOURCES.include?(resource)

      resource
    end
  end
end
