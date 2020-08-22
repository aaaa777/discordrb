require 'timeout'


module Discordrb::Voice

  # Audio data identify header
  AUDIO_DATA_IDENTIFIER = String.new("\x80x", encoding: ::Encoding::ASCII_8BIT)

  # grace time (ms / 1000)
  BUFFER_GRACE_TIME = 200.0 / 1000

  class PacketHandler
    attr_writer :master_filter

    def initialize(udp_socket, udp)
      @udp = udp
      @socket = udp_socket
      @user_ssrc = {}

      @await_threads = {}
      @dest_threads = nil
      #@await_threads[:all] = []
      
      # init packet reveiving loop
      @thread = Thread.new do
        Thread.current[:discordrb_name] = 'packet handler'

        recv_packet_loop
      end
      #@await_audio_threads = []
    end

    #def set_ssrc(user, ssrc)
    #  @user_ssrc[user.resolve_id] = ssrc.id
    #end

    def get_ssrc(user)
      @udp.get_ssrc
    end

    def start
      @packet_handling = true
    end

    def pause
      @packet_handling = false
    end

    def is_active?
      @packet_handling
    end

    # create io stream by recieved packets with user filter
    # block is given packet data and it should return decoded io buffer
    def create_io(**options, &block)
      user = options[:user].resolve_id if options[:user]
      reader, writer = IO.pipe
      Thread.new do
        Thread.current[:discordrb_name] = "#{user} voice stream"
        # debug
        #Thread.current[:recorder_log_mode] = options[:log_mode]
        push_io_loop(writer, **options, &block)
      end

      reader
    end

    #def create_event(**options, &block) plan

    # debug and private
    # blocking method
    # await packet receive flag
    # if you give a block this method, block given packet data and a value block returned would be await_packet return
    def await_packet(**options)
      # set default
      #options[:packet_type] = :all unless options[:packet_type]
      # make await thread and it list
      # block till receiving packet
      # @deprecated note: packet_type option may be used only :audio and :video in the future therefore named
      #   instance variables are used as awaiting thread array
      packet_type = options[:packet_type] ? options[:packet_type] : :all
      #user_id = options[:user_id]
      # default routing
      thread = Thread.new do
        Thread.current.name = "await #{packet_type} packet"
        current_th = Thread.current
        # received packet
        Thread.pass until @dest_threads && @dest_threads.include?(current_th) 

        block_given? ? yield(@received_packet_data) : @received_packet_data
      end
      
      # init packet type await
      # @await_threads[packet_type] = [] unless @await_threads[packet_type] 
      @await_threads[options] = thread
      p "awaits #{options}"
      # blocking thread till receive packet
      thread.join
      # block while @packet_was_received is true
      Thread.pass while @received_packet_data
      thread.value
    end

    # visiblity private
    # packethander#pause and this method are may helpful for fake packet debug
    # send packet to all awaiting methods via @received_packet_data
    # this method should add packet tags
    def receive_packet(data, **options)
      type = options[:packet_type] ? options[:packet_type] : :all
      #attribute = options[:packet_attr]
      #return unless type == :all
      # set data
      @received_packet_data = data
      #@received_packet_attr = attribute
      # set packet type
      @received_packet_type = type
      
      # emit objective threads
      @dest_threads = []
      @await_threads.delete_if{|key_options, th| match_options?(options, key_options) ? @dest_threads << th : nil}
      p "packet received #{options}, emit ths: #{@dest_threads.size}"
      # await threads
      @dest_threads.each{|th| th.join}
      #@await_threads[type].each{|th| th.join}
      #@await_threads[:all].each{|th| th.join}

      #@await_threads[type] = []
      #@await_threads[:all] = []

      # clear data 
      #@received_packet_attr = nil
      @received_packet_type = nil
      @received_packet_data = nil
      @dest_threads = nil
      
      # emit signal
      #@packet_was_received = true

      # reset signal(this signal releases await_packet completely)
      #@packet_was_received = false
    end

    private

    def match_options?(base_rule, match_rule)
      check_options = [:packet_type, :user]
      !match_rule.find do |option_key, rule|
        check_options.include?(option_key) && base_rule[option_key] != rule
      end
    end

    def push_io_loop(writer, **options)
      
      while true
        packet = await_packet(**options)
        buffer = yield(packet)
        p buffer, buffer.size
        writer.write(buffer)
      end
    end

    def push_io_loop2(writer, target, **options)
      type = options[:packet_type] ? options[:packet_type] : :all
      buffer_stack = {}
      next_seq = nil
      last_timestamp = Time.now
      sec = 0

      #packet_buffer_update_loop(buffer_stack, target, **options)
      # loop runs every adjust timing
      while true
        # use if buffer data exists
        buffer_data = buffer_stack[next_seq]

        # returns nil when timeout
        packet_data = await_next_packet(10, buffer: buffer_stack, next_sequence: next_seq, **options) unless buffer_data
        
        if packet_data
          # decode data
          # should catch errors?
          buffer_data = yield(packet_data)
          
          # write into writer io
          writer.write(buffer_data)
          increment_sequence(next_seq)
        else
          writer.write('silence audio')
          # whether buffer exists, packet will be desided to wait
          if buffer_stack.size > 2
            increment_sequence(next_seq)
            p 'p lost => next p'
          else
            #writer.write('waiting next packet')
            p 'wait p => seq is not changed'
          end
        end

        # should await buffer length + grace time
        #Thread.pass until last_timestamp + 0.1 >= Time.now

      end
      
    end

    # this method helps awaiting packet with timeout and filtering sequence(audio packet only now)
    def await_next_packet(timeout, buffer: buffer, next_sequence: next_seq = nil, **options)
      type = options[:packet_type]
      begin
        Timeout.new(timeout) do
          packet_data = nil
          while true
            # await a packet
            packet_data = await_packet(**options) do |packet|
              case type
              when :audio
                seq = packet[2..3].unpack1('n')
                next packet if seq == next_seq
                buffer[seq] = packet
              else
                packet
              end
            end

            break if packet_data
          end
          # return packet data
          packet_data
        end
      rescue Timeout::Error => exception
        nil
      end
    end


    # note: buffer grace time should be implemented
    def push_io_loop1(writer, user_id, **options, &block)

      decoder = Discordrb::Voice::Decoder.new
      type = options[:packet_type] ? options[:packet_type] : :all

      next_seq = nil
      last_ssrc = @user_ssrc[user_id]
      last_timestamp = nil
      buffer = {}
      p type
      # packet reveiving loop
      # await packet and execute block
      while true
        packet_data = nil
        seq = nil
        ssrc = nil
        # catch timeout exception
        begin
          packet_data = Timeout.timeout(BUFFER_GRACE_TIME) do
            data = nil
            # check buffer
            if next_seq && buffer[next_seq]
              data = buffer[next_seq] 
              buffer.delete(next_seq)
              case type
              when :all
                
              when :audio
                seq = data[2]
              else
                
              end
              next data.first
            end

            # await untill objective packet arrive
            while true
              # await new packet
              *data = await_packet(**options) do |packet|
                p "await called #{type}"
                # packet type filter
                case type
                  # when audio filter enabled
                  # note: this must be user filter arg
                when :audio
                  seq = packet[2..3].unpack1('n')
                  timestamp = packet[4..7].unpack1('N')
                  ssrc = packet[8..11].unpack1('N')
                  # drop packet other than specific user ssrc
                  next nil unless ssrc == @udp.get_ssrc(user_id)
                  [packet, ssrc, seq, timestamp]
                else
                  # return packet directry
                  [packet]
                end
              end
              next unless data.first
              p "data #{data}"
              # filter
              case type
              when :all
                break
              when :audio
                # first packet
                next_seq = seq unless next_seq
                # filter packet seq
                if seq == next_seq
                  break
                else
                  # buffer
                  buffer[seq] = data
                end 
                # next await
              end # end case

            end # end while
            # encounted objective sequence packet
            data.first
          end # end timeout
          
          # decode field
          writer.write(yield(packet_data))
          p seq, next_seq
          case next_seq
          when 0xff_ff
            next_seq = 0
          else
            next_seq += 1
          end
        rescue Timeout::Error => exception
          # skip packet for now
          #p 'push null io'
        end
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
          user = @udp.get_user(ssrc)
          p "[ssrc-#{ssrc}]: seq: #{seq}, timestamp: #{timestamp}, user: #{user}"
          
          receive_packet(packet_data, packet_type: :audio, ssrc: ssrc, sequence: seq, timestamp: timestamp, user: user)
        else
          # drop other than audio packets
          next (p "packet dropped id: #{packet_data[0..1]}, data: #{packet_data}")
          receive_packet(packet_data)
        end
        

      end
    end

    def increment_sequence(seq)
      case seq
      when nil
        # do nothing
        nil
      when 0xff_ff
        seq = 0
      else
        seq += 1
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

