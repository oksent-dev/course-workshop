module LocalAuthoring
  def self.enabled?
    (Rails.env.development? || Rails.env.test?) && Rails.configuration.x.local_authoring.enabled == true
  end

  def self.available?(request)
    enabled? && [ "127.0.0.1", "::1" ].include?(request.remote_ip) &&
      [ "localhost", "127.0.0.1", "::1", "[::1]" ].include?(request.host)
  end
end
