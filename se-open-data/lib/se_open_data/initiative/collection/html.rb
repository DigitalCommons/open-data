require 'se_open_data/utils/xml'
require 'se_open_data/utils/html'
require "se_open_data/utils/log_factory"

module SeOpenData
  class Initiative
    class Collection < Array
      class HTML
	      include SeOpenData::Utils::Xml	# for method xml()
	      include SeOpenData::Utils::Html

              # Create a log instance
              Log = SeOpenData::Utils::LogFactory.default
              
	      Title = "Contents of dataset"
	      attr_reader :collection, :config
	      def initialize(collection, config)
	        @collection, @config = collection, config
	      end
	      def save(outdir)
	        fname = collection.index_filename(outdir, ".html")
	        Log.info "Saving #{fname}..."
	        ::File.open(fname, "w") {|f| f.write(html(outdir)) }
	      end
	      def html(outdir)
	        "<!DOCTYPE html>\n" + 
	          xml(:html) {
	          xml(:head) {
              xml(:title) { Title } +
                xml(:meta, charset: "UTF-8") +
	              config.css_files.map {|f|
		            xml(:link, rel: "stylesheet", href: f)
	            }.join
	          } +
	            xml(:body) {
	            xml(:h1) { Title } +
	              table(
		              headers: ["Co-op name", "Locality", "URI"],
		              rows: collection.sort {|a, b| a.name <=> b.name }.map {|i|
		                [i.name, i.locality, link_to(i.rdf.uri, i.rdf.uri)]
		              }
	              )

	          }
	        }
	      end
      end
    end
  end
end
