
# encoder may load opus-ruby already
begin
  require 'opus-ruby'
  OPUS_AVAILABLE = true
rescue LoadError
  OPUS_AVAILABLE = false
end


# voice decoder
# sould this class definition be marged to encoder.rb?
module Discordrb::Voice
  # this class is only for decoding rtp packet data.
  class Decoder
    # create a new decoder
    def initialize
      sample_rate = 48_000
      frame_size = 960
      channels = 2
      @filter_volume = 1

      raise LoadError, 'Opus unavailable - voice not supported! Please install opus for voice support to work.' unless OPUS_AVAILABLE

      @opus = Opus::Decoder.new(sample_rate, frame_size, channels)
    end

    def decode(data)
      @opus.decode(data)
    end

    # reset decoder
    def reset
      @opus.reset
    end


  end
end