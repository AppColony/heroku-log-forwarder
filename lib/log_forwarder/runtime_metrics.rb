module LogForwarder
  module RuntimeMetrics
    require "time"

    RENDERED_LINE = /\A(?<timestamp>\S+)\s+heroku\[(?<dyno>[^\]]+)\]:\s+(?<rest>.*)\z/
    METRIC_PAIR = /sample#([a-zA-Z0-9_-]+)=([\d.]+)(MB|kB|GB|pages)?/

    def self.parse(source, dyno, timestamp, message)
      rendered = rendered_prefix(message)
      if rendered
        message = rendered[:rest]
      else
        timestamp = nil if timestamp.to_s.empty?
        dyno = nil if dyno.to_s.empty? || dyno == "-"
      end

      metrics = message.scan(METRIC_PAIR)
      return unless metrics.any?

      record = {
        "source" => source,
        "dyno_source" => dyno_source_from(message, rendered ? rendered[:dyno] : dyno),
        "logtype" => "heroku.runtime_metrics"
      }

      epoch_timestamp = epoch_milliseconds(rendered ? rendered[:timestamp] : timestamp)
      record["timestamp"] = epoch_timestamp if epoch_timestamp

      record.merge(
        metrics.to_h do |key, value, unit|
          name = key.tr("-", "_")
          name = "#{name}#{unit ? "_#{unit.downcase}" : ""}"
          [name, unit == "MB" ? value.to_f.round : value.to_f]
        end
      )
    end

    def self.dyno_source_from(message, fallback_dyno)
      message[/\bsource=(\S+)/, 1] || fallback_dyno
    end

    def self.rendered_prefix(message)
      message.match(RENDERED_LINE) if message&.match?(/\A\S+\s+heroku\[/)
    end

    def self.epoch_milliseconds(timestamp)
      return unless timestamp

      time = Time.iso8601(timestamp)
      time.to_i * 1000 + time.nsec / 1_000_000
    rescue ArgumentError
      nil
    end
  end
end