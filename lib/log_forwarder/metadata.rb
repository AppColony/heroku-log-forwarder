module LogForwarder
  module Metadata
    ROUTES = {
      "makeshift-staging" => "staging",
      "makeshift-prod" => "production"
    }.freeze

    ENV_VAR = "MAKESHIFT_ROUTE_METADATA"

    def self.resolve(source)
      return unless source.is_a?(String) && !source.empty?

      environment = ROUTES[source] || extension_routes[source]
      return unless environment

      {
        "makeshift_app" => source,
        "makeshift_environment" => environment
      }
    end

    def self.enrich(record, metadata)
      record.merge(metadata)
    end

    def self.extension_routes
      (ENV[ENV_VAR] || "").split(",").each_with_object({}) do |entry, routes|
        app, environment = entry.strip.split(":", 2)
        routes[app] = environment if app && !app.empty? && environment && !environment.empty?
      end
    end
  end
end