module LogForwarder
  module RuntimeMetrics
    LINE = /\A(?<timestamp>\S+)\s+heroku\[(?<dyno>[^\]]+)\]:\s+(?<rest>.*sample#.*)\z/

    def self.parse(source, line)
      match = line.match(LINE)
      return unless match

      metrics = match[:rest]
        .scan(/sample#([a-zA-Z0-9_]+)=([\d.]+)(MB|kB|GB|pages)?/)
        .to_h do |key, value, unit|
          name = "#{key}#{unit ? "_#{unit.downcase}" : ""}"
          [name, unit == "MB" ? value.to_f.round : value.to_f]
        end

      {
        "timestamp" => match[:timestamp],
        "source" => source,
        "dyno_source" => match[:dyno],
        "logtype" => "heroku.runtime_metrics"
      }.merge(metrics)
    end
  end
end
