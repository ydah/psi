# frozen_string_literal: true

require "etc"
require "timeout"

RSpec.describe "PSI on Linux" do
  before do
    skip "Linux PSI is unavailable" unless RUBY_PLATFORM.include?("linux") && PSI.supported?
  end

  def trigger_or_skip(resource, **options)
    PSI::Trigger.new(resource, **options)
  rescue PSI::UnsupportedError => e
    skip e.message
  rescue PSI::TriggerError => e
    raise unless e.message.match?(/EACCES|EPERM|EOPNOTSUPP|EBUSY/)

    skip e.message
  end

  def with_cpu_pressure
    workers = [[Etc.nprocessors * 2, 4].max, 16].min
    pids = workers.times.map { fork { loop { Math.sqrt(12_345) } } }
    yield
  ensure
    Process.kill("TERM", *pids) if pids&.any?
    pids&.each do |pid|
      Process.wait(pid)
    rescue Errno::ECHILD
      nil
    end
  end

  it "reads live system pressure" do
    reading = PSI.read(:memory)

    expect(reading.some.total).to be_a(Integer)
    expect(reading.full.total).to be_a(Integer)
  end

  it "registers a cgroup v2 pressure trigger" do
    trigger = trigger_or_skip(:memory, stall: 1.0, window: 10.0, cgroup: PSI.current_cgroup)

    expect(trigger).not_to be_closed
  ensure
    trigger&.close
  end

  it "receives a priority event and honors timeouts" do
    quiet = trigger_or_skip(:cpu, stall: 10.0, window: 10.0)
    expect(quiet.wait(timeout: 0.1)).to be(false)
    quiet.close

    active = trigger_or_skip(:cpu, stall: 0.001, window: 0.5)
    with_cpu_pressure { expect(active.wait(timeout: 5)).to be(true) }
  ensure
    quiet&.close
    active&.close
  end

  it "monitors multiple triggers on one thread" do
    events = Queue.new
    monitor = PSI::Monitor.new
    2.times { monitor.on(:cpu, stall: 0.001, window: 0.5) { |event| events << event } }
    monitor.start

    with_cpu_pressure do
      received = Timeout.timeout(5) { 2.times.map { events.pop } }
      expect(received).to all(be_a(PSI::Event))
    end
  rescue PSI::TriggerError, PSI::UnsupportedError => e
    skip e.message
  ensure
    monitor&.stop
  end

  it "does not leak trigger descriptors" do
    before = Dir.children("/proc/self/fd").length
    1_000.times { trigger_or_skip(:cpu, stall: 10.0, window: 10.0).close }
    GC.start

    expect(Dir.children("/proc/self/fd").length).to be <= before + 1
  end
end
