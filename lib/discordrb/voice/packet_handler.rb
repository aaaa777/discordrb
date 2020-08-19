
module Discordrb::Voice

  # Audio data identify header
  AUDIO_DATA_IDENTIFIER = String.new("\x90x", encoding: ::Encoding::ASCII_8BIT)

  class PacketHandler
    def initialize(udp_socket)
      @socket = udp_socket
      @user_ssrc = {}

      @await_threads = {}

      @received_packet_data = nil
      
      # init packet reveiving loop
      @thread = Thread.new do
        Thread.current[:discordrb_name] = 'packet handler'

        recv_packet_loop
      end
      #@await_audio_threads = []
    end

    def set_ssrc(user, ssrc)
      @user_ssrc[user.resolve_id] = ssrc.id
    end

    def start
      @packet_handling = true
      return
      
      if @thread
        @thread.run
      else

      end
    end

    def pause
      @packet_handling = false
      #@thread.stop
    end

    # create io stream by recieved packets with user filter
    # block is given packet data and it should return io buffer
    def create_io(user, **options, &block)
      user = user.resolve_id
      reader, writer = IO.pipe
      Thread.new do
        Thread.current[:discordrb_name] = "#{user} voice stream"
        # debug
        #Thread.current[:recorder_log_mode] = options[:log_mode]
        push_io_loop(writer, user, **options, &block)
      end

      reader
    end

    # debug and private
    # blocking method
    # await packet receive flag
    def await_packet(**options)
      # set default
      #options[:packet_type] = :all unless options[:packet_type]
      # make await thread and it list
      # block till receiving packet
      # @note: packet_type option may be used only :audio and :video in the future therefore named
      #   instance variables are used as awaiting thread array
      packet_type = options[:packet_type] ? options[:packet_type] : :all
      # default routing
      thread = Thread.new do
        Thread.current.name = "await #{packet_type} packet"
        case packet_type
        when :all
          Thread.pass until @received_packet_data
        else
          Thread.pass until @received_packet_data && @received_packet_type == packet_type
        end
        p @received_packet_data
        yield(@received_packet_data) if block_given?
      end

      # init packet type await
      @await_threads[packet_type] = [] unless @await_threads[packet_type] 
      @await_threads[packet_type] << thread
      
      # blocking thread till receive packet
      thread.join
      # block while @packet_was_received is true
      Thread.pass while @received_packet_data
      thread.value
    end

    # visiblity private
    # packethander#pause and this method are may helpful for fake packet debug
    # send packet to all awaiting methods via @received_packet_data
    def receive_packet(data, **options)
      raise
      p data, options
      type = options[:packet_type] ? options[:packet_type] : :all
      return unless @await_threads[type] || type == :all
      # set data
      @received_packet_data = data

      # set packet type
      @received_packet_type = type
      
      
      @await_threads[type].each{|th| th.join}
      @await_threads[:all].each{|th| th.join}

      @await_threads[type] = []
      @await_threads[:all] = []

      # clear data 
      @received_packet_data = nil
      @received_packet_type = nil
      
      # emit signal
      #@packet_was_received = true

      # reset signal(this signal releases await_packet completely)
      #@packet_was_received = false
    end

    private


    # note: buffer grace time should be implemented
    def push_io_loop(writer, user_id, **options, &block)

      decoder = Discordrb::Voice::Decoder.new

      next_seq = nil
      last_ssrc = @user_ssrc[user_id]
      last_timestamp = nil
      buffer = {}

      # packet reveiving loop
      while true
        # await packet and execute block
        await_packet(**options, &block)# do |audio_data, ssrc, seq, timestamp|

      end
    end


    def recv_packet_loop
      while true
        Thread.pass until @packet_handling
        
        # 500 has no meaning actually
        packet_data = @socket.recv(500)
        packet_data.force_encoding('ASCII-8BIT')
        
        case packet_data[0..1]
        when AUDIO_DATA_IDENTIFIER
          # for debug
          seq = packet_data[2..3].unpack1('n')
          timestamp = packet_data[4..7].unpack1('N')
          ssrc = packet_data[8..11].unpack1('N')
          p "[ssrc-#{ssrc}]: seq: #{seq}, timestamp: #{timestamp}"
          
          receive_packet(packet_data, packet_type: :audio)
        else
          # drop other than audio packets
          next (p "packet dropped id: #{packet_data[0..1]}, data: #{packet_data}")
          receive_packet(packet_data)
        end
        

      end
    end



  end
  
  # depricated class
  class Packet
  
  attr_accessor :data, :info, :seq, :payload_type, :cc, :datalen, :ssrc, :flg, :timestamp
  
    # bit mask
      FLAG_MASK = { 
      padding: 8192,   # 0010 0000 0000 0000
      extention: 4096, # 0001 0000 0000 0000
      marker: 128      # 0000 0000 1000 0000
    }
  
    def initialize(raw_data, filter_option = {})
      @data = raw_data
      @bdata = raw_data.bytes
      @info, @seq, _32_1, _32_2 = @data.unpack('nnNN')
      #p 'audio packet' if @info == VOICE_PACKET_HEADER
      
      
      binfo = sprintf("%#018b", info)
      @payload_type = binfo[11..17].to_i(2)
      @cc = binfo[6..9].to_i(2)
      
      
      @datalen = data.size
      @flg = @info & FLAG_MASK[:extention] > 0
      if @cc == 0
        @ssrc = data[8..11].unpack1('N') 
        @timestamp = data[4..7].unpack1('N')
      else
        @ssrc = data[4..7].unpack1('N')
        @timestamp = nil
      end       
      
      
    end
  end
end

