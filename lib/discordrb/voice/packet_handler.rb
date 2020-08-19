
# deprecated class
module Discordrb::Voice

  class PacketHandler
    def initialize(udp_socket)
      @socket = udp_socket
      @buff = []

    end

    def start
      @packet_handling = true
      return
      
      if @thread
        @thread.run
      else
        @thread = Thread.new do
          Thread.current[:discordrb_name] = 'packet-hundler'
          recv_packet_loop
        end
      end
    end

    def stop
      @packet_handling = false
      #@thread.stop
    end

    #create io stream by recieved packets with user filter
    def create_io(user)
      user.resolve_id

    end

    def recv_packet_loop
      @packet_handling = true
      while true
        data = @socket.recv(500)

        seq = data[2..3]
        timestamp = data[4..7].unpack('N')
        ssrc = data[8..11].unpack('N')

        sleep 0.1 while !@packet_handling
        p "#{ssrc}, #{seq}, #{timestamp}"
      end
    end

  end


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

