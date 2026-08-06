require 'linkeddata'
require 'rdf/rdfxml'
require 'net/http'
require 'se_open_data/utils/log_factory'

module SeOpenData
  module Essglobal
    class Standard
      # Create a log instance
      Log = SeOpenData::Utils::LogFactory.default
      
      attr_reader :uri
      
      # taxonomy is a string that matches one of the filenames (but without `.skos`) in:
      # https://github.com/essglobal-linked-open-data/map-sse/tree/develop/vocabs/standard
      def initialize(essglobal_uri, taxonomy)
        @uri = "#{essglobal_uri}standard/#{taxonomy}"

        #hardcode to test -- error looking at old url
        Log.info "Loading graph from URL: #{@uri}"
        graph = ::RDF::Graph.load(@uri, format: :rdfxml)
        query = ::RDF::Query.new do
          pattern [:concept, ::RDF.type, ::RDF::Vocab::SKOS.Concept]
          pattern [:concept, ::RDF::Vocab::SKOS.prefLabel, :label]
        end
        @lookup = {}
        @concepts = {}
        query.execute(graph).each do |solution|
          @lookup[to_key(solution.label.to_s)] = solution
          @concepts[solution.concept.to_s] = solution
        end
      end

      def get_redirect_url(url)
	    url = URI.parse(url)
	    res = Net::HTTP.start(url.host, url.port) {|http|
		  http.get(url.request_uri)
		}

	    if res['location']
		return res['location'] 
	    else
		return url
      	    end
	    end

      def has_label? (label)
        @concepts.has_key?(label) || @lookup.has_key?(to_key(label))
      end
      def concept_uri(label)
        solution = @concepts[label] || @lookup[to_key(label)]
        solution.concept.to_s
      end
      def has_concept?(concept)
        @concepts.has_key?(concept.to_s)
      end
      private
      def to_key(label)
        label.upcase.gsub(/ /, "")
      end
    end
  end
end


