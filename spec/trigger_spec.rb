# frozen_string_literal: true

RSpec.describe PSI::Trigger do
  FakeIO = Struct.new(:written, :sync, :closed, :wait_result) do
    def write(value) = self.written = value
    def close = self.closed = true
    def closed? = !!closed
    def wait(*) = wait_result
  end

  let(:io) { FakeIO.new }

  before do
    allow(File).to receive(:open).and_return(io)
  end

  it "registers a trigger with rounded microseconds" do
    trigger = described_class.new(:memory, stall: 0.15, window: 1.0)

    expect(File).to have_received(:open).with("/proc/pressure/memory", File::RDWR)
    expect(io.sync).to be(true)
    expect(io.written).to eq("some 150000 1000000\n")
    expect(trigger).not_to be_closed
  end

  it "validates arguments before opening a file" do
    expect { described_class.new(:memory, stall: 0.1, window: 0.49) }.to raise_error(ArgumentError, /window/)
    expect { described_class.new(:memory, stall: 1.1, window: 1.0) }.to raise_error(ArgumentError, /exceed/)
    expect { described_class.new(:memory, kind: :other, stall: 0.1, window: 1.0) }.to raise_error(ArgumentError, /kind/)
    expect { described_class.new(:cpu, kind: :full, stall: 0.1, window: 1.0) }.to raise_error(ArgumentError, /cpu/)
    expect(File).not_to have_received(:open)
  end

  it "allows cpu full for a cgroup with a warning" do
    expect do
      described_class.new(:cpu, kind: :full, stall: 0.1, window: 1.0, cgroup: "/cg")
    end.to output(/may be unavailable/).to_stderr
    expect(io.written).to eq("full 100000 1000000\n")
  end

  it "converts registration failures and closes the descriptor" do
    allow(io).to receive(:write).and_raise(Errno::EBUSY)

    expect { described_class.new(:io, stall: 0.1, window: 1.0) }.to raise_error(PSI::TriggerError, /EBUSY/)
    expect(io).to be_closed
  end

  it "waits for priority events and rejects use after close" do
    io.wait_result = io
    trigger = described_class.new(:memory, stall: 0.1, window: 1.0)
    expect(trigger.wait(timeout: 2)).to be(true)

    trigger.close
    expect(trigger).to be_closed
    expect { trigger.wait }.to raise_error(PSI::Error, /closed/)
  end

  it "closes block-form triggers even when the block fails" do
    expect do
      described_class.open(:memory, stall: 0.1, window: 1.0) { raise "boom" }
    end.to raise_error("boom")
    expect(io).to be_closed
  end
end
