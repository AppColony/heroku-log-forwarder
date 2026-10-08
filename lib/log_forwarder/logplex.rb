module LogForwarder
  module Logplex
    SYSLOG_MESSAGE = /\A(?<pri><\d+>)?(?<version>\d+)\s+(?<timestamp>\S+)\s+(?<host>\S+)\s+(?<app>\S+)\s+(?<procid>\S+)\s+-\s+(?<message>.*)\z/

    class InvalidFrame < StandardError; end

    def self.frames(payload)
      frames = []
      offset = 0

      while offset < payload.bytesize
        offset += 1 while payload.byteslice(offset)&.match?(/\s/)
        break if offset >= payload.bytesize

        delimiter = payload.index(" ", offset)
        raise InvalidFrame, "invalid Logplex frame" unless delimiter

        length = Integer(payload.byteslice(offset...delimiter), 10)
        frame_start = delimiter + 1
        frame = payload.byteslice(frame_start, length)
        raise InvalidFrame, "truncated Logplex frame" unless frame&.bytesize == length

        frames << frame
        offset = frame_start + length
      end

      frames
    rescue ArgumentError
      raise InvalidFrame, "invalid Logplex frame length"
    end

    def self.message(frame)
      frame.match(SYSLOG_MESSAGE)&.[](:message)
    end

    def self.parse(frame)
      parts = frame.match(SYSLOG_MESSAGE)
      return unless parts

      keys = %w[timestamp host app procid message]
      keys.zip(parts.names.zip(parts.captures).to_h.values_at(*keys)).to_h
    end
  end
end
