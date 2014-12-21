# Celluloid mailboxes are the universal message exchange points. You won't
# be able to marshal them though, unfortunately, because they contain
# mutexes.
#
# DCell provides a message routing layer between nodes that can direct
# messages back to local mailboxes. To accomplish this, DCell adds custom
# marshalling to mailboxes so that if they're unserialized on a remote
# node you instead get a proxy object that routes messages through the
# DCell overlay network back to the node where the actor actually exists

module Celluloid
  class Mailbox
    def to_msgpack(pk=nil)
      DCell::MailboxManager.register self
      {
        :address => @address,
        :id      => DCell.id
      }.to_msgpack(pk)
    end
  end

  class CellProxy
    alias_method :____async, :async
    def async(meth = nil, *args, &block)
      raise DeadActorError.new unless alive?
      ____async meth, *args, &block
    end

    alias_method :____future, :future
    def future(meth = nil, *args, &block)
      raise DeadActorError.new unless alive?
      ____future meth, *args, &block
    end
  end
end
