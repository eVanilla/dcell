module DCell
  # Servers handle incoming 0MQ traffic
  module MessageHandler
    class InvalidMessageError < StandardError; end
    extend self

    # Handle incoming messages
    def handle_message(message)
      begin
        message = decode_message message
      rescue InvalidMessageError => ex
        Logger.crash("couldn't decode message", ex)
        return
      end

      begin
        message.dispatch
      rescue => ex
        Logger.crash("message dispatch failed", ex)
      end
    end

    # Decode incoming messages
    def decode_message(message)
      begin
        msg = MessagePack.unpack(message, symbolize_keys: true)
      rescue => ex
        raise InvalidMessageError, "couldn't unpack message: #{ex}"
      end
      begin
        klass = Utils.full_const_get msg[:type]
        o = klass.new(*msg[:args])
        o.id = msg[:id] if o.respond_to?(:id=) && msg[:id]
        o
      rescue => ex
        raise InvalidMessageError, "invalid message: #{ex}"
      end
    end
  end

  class Server
    include Celluloid::ZMQ
    include MessageHandler

    attr_accessor :farewell
    finalizer :shutdown

    # Bind to the given 0MQ address (in URL form ala tcp://host:port)
    def initialize(socket)
      @socket = socket
      @farewell = false
      async.run
    end

    def shutdown
      return unless @socket
      if @farewell
        msg = Message::Farewell.new.to_msgpack
        @socket.write msg
      end
      @socket.close
      instance_variables.each { |iv| remove_instance_variable iv }
    end

    def write(id, msg)
      if @socket.is_a? Celluloid::ZMQ::RouterSocket
        @socket.write id, msg
      else
        @socket.write msg
      end
    end

    # Wait for incoming 0MQ messages
    def run
      while true
        message = @socket.read_multipart
        if @socket.is_a? Celluloid::ZMQ::RouterSocket
          message = message[1]
        else
          message = message[0]
        end
        handle_message message
      end
    end
  end

  # Sets up main DCell request server
  class RequestServer < Server
    def initialize
      socket, addr = Socket.server(DCell.addr, DCell.id)
      DCell.addr = addr
      super(socket)
    end
  end

  # Sets up node relay server
  class RelayServer < Server
    attr_reader :addr

    def initialize
      uri = URI(DCell.addr)
      addr = "#{uri.scheme}://#{uri.host}:*"
      socket, @addr = Socket.server(addr, DCell.id)
      super(socket)
    end
  end

  # Sets up client server
  class ClientServer < Server
    def initialize(addr, linger)
      socket = Socket.client(addr, DCell.id, linger)
      super(socket)
    end
  end
end
