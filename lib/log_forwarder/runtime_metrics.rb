module LogForwarder
  module RuntimeMetrics
    require "time"

    RENDERED_LINE = /\A(?<timestamp>\S+)\s+heroku\[(?<dyno>[^\]]+)\]:\s+(?<rest>.*)\z/
    METRIC_PAIR = /sample#([a-zA-Z0-9_-]+)=([\d.]+)(MB|kB|GB|pages)?/

    # Heroku emits this metric under plural (Heroku Postgres) and singular
    # (Heroku Redis) spellings; normalize to the singular so one NRQL
    # attribute serves both.
    SYNONYM_KEYS = { "connections_percentage_used" => "connection_percentage_used" }.freeze

    RUNTIME_METRICS_LOGTYPE = "heroku.runtime_metrics"
    ADDON_METRICS_LOGTYPE = "heroku.addon_metrics"

    def self.parse(source, dyno, timestamp, message)
      rendered = rendered_prefix(message)
      if rendered
        message = rendered[:rest]
        logtype = RUNTIME_METRICS_LOGTYPE
      else
        timestamp = nil if timestamp.to_s.empty?
        logtype = dyno ? RUNTIME_METRICS_LOGTYPE : ADDON_METRICS_LOGTYPE
        dyno = nil if dyno.to_s.empty? || dyno == "-"
      end

      metrics = message.scan(METRIC_PAIR)
      return unless metrics.any?

      record = {
        "source" => source,
        "dyno_source" => dyno_source_from(message, rendered ? rendered[:dyno] : dyno),
        "logtype" => logtype
      }

      epoch_timestamp = epoch_milliseconds(rendered ? rendered[:timestamp] : timestamp)
      record["timestamp"] = epoch_timestamp if epoch_timestamp

      record.merge(
        metrics.to_h do |key, value, unit|
          name = key.tr("-", "_")
          name = SYNONYM_KEYS.fetch(name, name)
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