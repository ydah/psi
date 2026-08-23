# frozen_string_literal: true

RSpec.describe PSI::Event do
  it "formats the trigger and current pressure" do
    trigger = instance_double(PSI::Trigger, resource: :memory, kind: :some, stall: 0.15, window: 1.0)
    reading = PSI::Reading.parse(:memory, "some avg10=12.3 total=1\n")

    event = described_class.new(trigger: trigger, reading: reading)

    expect(event.to_s).to eq("memory some avg10=12.3% (threshold 150ms/1s)")
  end
end
