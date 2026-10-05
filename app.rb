require "fluent-logger"
require "sinatra/base"

require_relative "lib/log_forwarder/logplex"
require_relative "lib/log_forwarder/runtime_metrics"

class LogForwarderApp < Sinatra::Base
  set :bind, "0.0.0.0"
  set :show_exceptions, false
  set :host_authorization, { permitted_hosts: [] }
  set :fluent_logger, unless environment == :test
    Fluent::Logger::FluentLogger.new(
      nil,
      host: "127.0.0.1",
      port: 24_224,
      timeout: 1
    )
  end

  post "/newrelic/:source" do
    LogForwarder::Logplex.frames(request.body.read).each do |frame|
      line = LogForwarder::Logplex.message(frame)
      record = line && LogForwarder::RuntimeMetrics.parse(params["source"], line)
      settings.fluent_logger.post("heroku.runtime_metrics", record) if record
    end

    status 200
    headers "Content-Length" => "0"
    body ""
  rescue LogForwarder::Logplex::InvalidFrame
    halt 400
  end

  get "/healthz" do
    "OK"
  end
end
