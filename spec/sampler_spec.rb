# frozen_string_literal: true

RSpec.describe PSI::Sampler do
  def reading(some, full)
    PSI::Reading.parse(:memory, "some total=#{some}\nfull total=#{full}\n")
  end

  it "calculates ratios and clamps reset counters to zero" do
    allow(PSI).to receive(:read).and_return(reading(100_000, 10_000), reading(250_000, 5_000))
    allow(Process).to receive(:clock_gettime).and_return(10.0, 15.0)
    sampler = described_class.new(:memory)

    expect(sampler.sample).to be_nil
    delta = sampler.sample
    expect(delta.some_ratio).to eq(0.03)
    expect(delta.full_ratio).to eq(0.0)
    expect(delta.elapsed).to eq(5.0)
  end
end
