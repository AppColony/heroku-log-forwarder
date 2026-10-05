workers 0
threads 1, 1
port ENV.fetch("PORT", 8080)
environment ENV.fetch("RACK_ENV", "production")
rackup "config.ru"
