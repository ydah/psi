# frozen_string_literal: true

require_relative "psi/version"
require_relative "psi/reading"
require_relative "psi/sampler"
require_relative "psi/trigger"
require_relative "psi/event"
require_relative "psi/monitor"

# Reads Linux Pressure Stall Information (PSI).
module PSI
  # Resource names exposed by Linux PSI.
  RESOURCES = %i[cpu memory io irq].freeze

  # Base error for PSI-specific failures.
  class Error < StandardError; end
  # Raised when the running kernel does not expose the requested PSI feature.
  class UnsupportedError < Error; end
  # Raised when the kernel rejects trigger registration.
  class TriggerError < Error; end

  class << self
    attr_writer :procfs_root

    def procfs_root
      @procfs_root ||= "/proc"
    end

    def supported?
      File.directory?(File.join(procfs_root, "pressure"))
    end

    # Returns resources available under the configured procfs root.
    # @return [Array<Symbol>]
    def resources
      RESOURCES.select { |resource| File.file?(path_for(resource)) }
    end

    # Reads one system-wide or cgroup pressure resource.
    # @param resource [Symbol, String]
    # @param cgroup [String, nil] cgroup v2 directory, or nil for procfs
    # @return [Reading]
    def read(resource, cgroup: nil)
      resource = validate_resource(resource)
      Reading.parse(resource, File.read(path_for(resource, cgroup: cgroup)))
    rescue Errno::ENOENT, Errno::EOPNOTSUPP => e
      raise UnsupportedError, e.message
    end

    # Reads every pressure resource available at the target location.
    # @param cgroup [String, nil] cgroup v2 directory, or nil for procfs
    # @return [Hash{Symbol => Reading}]
    def read_all(cgroup: nil)
      available = cgroup ? RESOURCES.select { |resource| File.file?(path_for(resource, cgroup: cgroup)) } : resources
      available.to_h { |resource| [resource, read(resource, cgroup: cgroup)] }
    end

    # Resolves this process's unified cgroup v2 directory.
    # @return [String]
    def current_cgroup
      entry = File.foreach(File.join(procfs_root, "self/cgroup")).find { |line| line.start_with?("0::") }
      raise UnsupportedError, "cgroup v2 is not mounted" unless entry

      File.join("/sys/fs/cgroup", entry.split("::", 2).last.strip.delete_prefix("/"))
    rescue Errno::ENOENT => e
      raise UnsupportedError, e.message
    end

    # Builds the backing file path for a resource.
    # @api private
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
