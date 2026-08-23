# frozen_string_literal: true

RSpec.describe PSI::Monitor do
  let(:trigger_io) { Object.new }
  let(:trigger) do
    instance_double(
      PSI::Trigger,
      to_io: trigger_io,
      resource: :memory,
      kind: :some,
      stall: 0.1,
      window: 1.0,
      cgroup: nil,
      close: nil
    )
  end

  before do
    allow(PSI::Trigger).to receive(:new).and_return(trigger)
    allow(PSI).to receive(:read).and_return(PSI::Reading.parse(:memory, "some avg10=1 total=1\n"))
  end

  it "delivers events and closes triggers" do
    delivered = Queue.new
    monitor = described_class.new.on(:memory, stall: 0.1, window: 1.0) { |event| delivered << event }
    select_calls = 0
    allow(IO).to receive(:select) do |readers, _, priorities|
      select_calls += 1
      select_calls == 1 ? [[], [], priorities] : [[readers.first], [], []]
    end

    monitor.start
    expect(delivered.pop.resource).to eq(:memory)
    monitor.stop

    expect(trigger).to have_received(:close)
  end

  it "reports callback errors and keeps selecting" do
    errors = Queue.new
    monitor = described_class.new
    monitor.on_error { |error| errors << error }
    monitor.on(:memory, stall: 0.1, window: 1.0) { raise "callback failed" }
    select_calls = 0
    allow(IO).to receive(:select) do |readers, _, priorities|
      select_calls += 1
      select_calls == 1 ? [[], [], priorities] : [[readers.first], [], []]
    end

    monitor.start
    expect(errors.pop.message).to eq("callback failed")
    monitor.stop

    expect(select_calls).to eq(2)
  end

  it "wakes an idle monitoring thread on stop" do
    monitor = described_class.new
    monitor.start

    expect { monitor.stop }.not_to raise_error
  end
end
