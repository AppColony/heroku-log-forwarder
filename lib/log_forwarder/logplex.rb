module LogForwarder
  module Logplex
    SYSLOG_MESSAGE = /\A<\d+>\d+\s+\S+\s+\S+\s+\S+\s+\S+\s+-\s+(?<message>.*)\z/

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
  end
end
