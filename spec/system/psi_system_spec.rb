# frozen_string_literal: true

require "etc"
require "timeout"

RSpec.describe "PSI on Linux" do
  before do
    skip "Linux PSI is unavailable" unless RUBY_PLATFORM.include?("linux") && PSI.supported?
  end

  def trigger_or_skip(resource, **options)
    PSI::Trigger.new(resource, **options)
  rescue PSI::UnsupportedError, PSI::TriggerError => e
    raise if ENV["PSI_REQUIRE_TRIGGERS"] == "1" || !e.message.match?(/EACCES|EPERM|EOPNOTSUPP|EBUSY/)

    skip e.message
  end

  def with_memory_cgroup
    cgroup = PSI.current_cgroup
    high = File.join(cgroup, "memory.high")
    pressure = File.join(cgroup, "memory.pressure")
    raise "the current cgroup does not expose memory.high" unless Process.uid.zero? && File.file?(high)

    original_high = File.read(high)
    File.write(high, (64 * 1024 * 1024).to_s)
    yield cgroup, pressure
  rescue PSI::UnsupportedError, SystemCallError, RuntimeError => e
    raise if ENV["PSI_REQUIRE_CGROUP"] == "1"

    skip e.message
  ensure
    File.write(high, original_high) if original_high
  end

  def register_as_nobody(cgroup, pressure)
    owner = File.stat(pressure)
    nobody = Etc.getpwnam("nobody")
    File.chown(nobody.uid, nobody.gid, pressure)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      Process::GID.change_privilege(nobody.gid)
      Process::UID.change_privilege(nobody.uid)
      PSI::Trigger.open(:memory, stall: 0.001, window: 2.0, cgroup: cgroup) {}
      writer.write("ok")
      writer.close
      exit!(0)
    rescue StandardError => e
      writer.write(e.full_message)
      writer.close
      exit!(1)
    end
    writer.close
    result = reader.read
    _, status = Timeout.timeout(3) { Process.wait2(pid) }
    pid = nil
    raise result unless status.success?
  ensure
    reader&.close
    File.chown(owner.uid, owner.gid, pressure) if owner
    terminate(pid)
  end

  def terminate(pid, signal = "TERM")
    return unless pid

    Process.kill(signal, pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
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

  def with_memory_pressure
    # ponytail: fixed load for the isolated CI cgroup; make proportional if its limit becomes configurable.
    pid = fork do
      chunks = []
      loop do
        chunks << "x" * (1024 * 1024)
        chunks.shift if chunks.length > 160
      end
    end
    yield
  ensure
    terminate(pid, "KILL")
  end

  it "reads live system pressure" do
    readings = PSI.read_all
    reading = readings.fetch(:memory)
    trigger = trigger_or_skip(:memory, stall: 10.0, window: 10.0)

    expect(readings.keys).to include(:cpu, :memory, :io)
    if readings.key?(:irq)
      expect(readings.fetch(:irq).some).to be_nil
      expect(readings.fetch(:irq).full.total).to be_a(Integer)
    end
    expect(reading.some.total).to be_a(Integer)
    expect(reading.full.total).to be_a(Integer)
    expect(trigger).not_to be_closed
  ensure
    trigger&.close
  end

  it "registers an unprivileged cgroup trigger and detects memory pressure within two seconds" do
    with_memory_cgroup do |cgroup, pressure|
      register_as_nobody(cgroup, pressure)
      trigger = PSI::Trigger.new(:memory, stall: 0.001, window: 0.5, cgroup: cgroup)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      with_memory_pressure do
        expect(trigger.wait(timeout: 2)).to be(true)
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be <= 2.0
      end
    ensure
      trigger&.close
    end
  end

  it "receives a priority event and honors timeouts" do
    quiet = trigger_or_skip(:cpu, stall: 10.0, window: 10.0)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect(quiet.wait(timeout: 1)).to be(false)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be_between(0.9, 1.5)
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
    raise if ENV["PSI_REQUIRE_TRIGGERS"] == "1"

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
