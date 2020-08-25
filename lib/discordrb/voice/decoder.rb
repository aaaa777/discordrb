
# encoder may load opus-ruby already
#begin
#  require 'opus-ruby'
#  OPUS_AVAILABLE = true
#rescue LoadError
#  OPUS_AVAILABLE = false
#end

module Opus
  class Decoder
    def decode( data )
      len = data.size

      packet = FFI::MemoryPointer.new :char, len + 1
      packet.put_string 0, data

      max_size = @frame_size * @channels * 2 # Was getting buffer_too_small errors without the 2

      decoded = FFI::MemoryPointer.new :short, max_size + 1

      frame_size = Opus.opus_decode @decoder, packet, len, decoded, max_size, 0

      # The times 2 is very important and caused much grief prior to an IRC
      # chat with the Opus devs. Just remember a short is 2 bytes... Seems so
      # simple now...
      return decoded.read_string_length frame_size * 2
    end
  end  
end

# voice decoder
# should this class definition be marged into encoder.rb?
module Discordrb::Voice
  # this class is only for decoding rtp packet data.

  class Decoder
    # create a new decoder
    def initialize
      sample_rate = 48_000
      frame_size = 960
      channels = 1
      #@filter_volume = 1

      raise LoadError, 'Opus unavailable - voice not supported! Please install opus for voice support to work.' unless OPUS_AVAILABLE

      @opus = Opus::Decoder.new(sample_rate, frame_size, channels)
    end

    def decode(data)
      @opus.decode(data).force_encoding('ASCII-8BIT')
    end

    # reset decoder
    def reset
      @opus.reset
    end


  end
end
