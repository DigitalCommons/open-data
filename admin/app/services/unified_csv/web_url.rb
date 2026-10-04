# Just enough of the WHATWG URL parser (JavaScript's `new URL`) to tell, as
# clean-csv-data does, whether a website is a valid http(s) URL, its host
# and whether it has a path beyond "/". Ruby's URI is stricter (it rejects
# Unicode hosts, for one), so it cannot stand in.
module UnifiedCsv
  module WebUrl
    Parsed = Data.define(:host, :path)

    SCHEME = /\A([a-zA-Z][a-zA-Z0-9+.\-]*):(.*)\z/m
    # Code points WHATWG forbids in a host
    FORBIDDEN_HOST = /[\u0000\t\n\r #\/:<>?@\[\\\]^|%]/

    # Parsed host (lowercased) and path, or nil where `new URL` would throw.
    # Only http and https are parsed; anything else is treated as invalid.
    def self.parse(string)
      string = string.gsub(/[\t\n\r]/, "").gsub(/\A[\u0000- ]+|[\u0000- ]+\z/, "")
      match = SCHEME.match(string) or return nil
      return nil unless %w[ http https ].include?(match[1].downcase)

      rest = match[2].sub(%r{\A[/\\]*}, "")
      authority, remainder = rest.split(%r{(?=[/\\?#])}, 2)
      authority = authority.to_s.sub(/\A.*@/m, "")
      host, port = split_port(authority)
      return nil if host.nil? || host.empty? || host.match?(FORBIDDEN_HOST)
      return nil unless port.nil? || port.match?(/\A\d*\z/)

      Parsed.new(host: host.downcase, path: normalise_path(remainder.to_s))
    end

    def self.split_port(authority)
      if authority.start_with?("[")
        close = authority.index("]") or return [ nil, nil ]
        [ authority[0..close], authority[(close + 1)..].delete_prefix(":").presence ]
      else
        host, port = authority.split(":", 2)
        [ host, port ]
      end
    end

    def self.normalise_path(remainder)
      path = remainder.split(/[?#]/, 2).first.to_s.tr("\\", "/")
      segments = []
      path.split("/", -1).drop(1).each do |segment|
        case segment.downcase
        when ".", "%2e" then next
        when "..", ".%2e", "%2e.", "%2e%2e" then segments.pop
        else segments << segment
        end
      end
      "/" + segments.join("/")
    end

    private_class_method :split_port, :normalise_path
  end
end
