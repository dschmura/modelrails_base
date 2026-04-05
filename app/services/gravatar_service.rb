class GravatarService
  def self.check(email)
    hash = Digest::SHA256.hexdigest(email.strip.downcase)
    uri = URI("https://www.gravatar.com/avatar/#{hash}?d=404")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
      http.head(uri.request_uri)
    end
    response.code == "200"
  rescue StandardError
    false
  end
end
