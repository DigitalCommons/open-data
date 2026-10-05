module Mykomap
  # Property definitions, ported from libs/common/src/prop-defs.ts.
  # Specs are string-keyed hashes as produced by Mykomap::Config.parse.
  module PropDefs
    class Error < StandardError; end

    # Builds PropDef instances from a vocab index and prop specs.
    class Factory
      attr_reader :vocabs

      # @param vocabs - the config's vocab index
      # @param check_langs - optional language codes each vocab must cover
      def initialize(vocabs, check_langs = nil)
        @vocabs = vocabs
        if check_langs
          invalid = vocabs.reject { |_id, i18n| check_langs.all? { |lang| i18n.key?(lang) } }.keys
          if invalid.any?
            raise Error, "vocabs incompatible with the target languages '#{check_langs.join(',')}': #{invalid.join(',')}"
          end
        end
      end

      def i18n_vocab_def(uri)
        abbrev = uri.sub(/:\z/, "")
        vocabs[abbrev] or raise Error, "unknown vocab URI: '#{uri}'"
      end

      def mk_prop_def(spec)
        case spec["type"]
        when "value" then ValuePropDef.new(spec)
        when "vocab" then VocabPropDef.new(spec, i18n_vocab_def(spec["uri"]))
        when "multi" then MultiPropDef.new(spec, mk_prop_def(spec["of"]))
        else raise Error, "unknown prop type: #{spec['type']}"
        end
      end

      # @return a Hash of prop name -> PropDef
      def mk_prop_defs(specs)
        specs.transform_values { |spec| mk_prop_def(spec) }
      end
    end

    class Common
      attr_reader :from, :title_uri, :filter, :search

      def initialize(spec)
        @from = spec["from"]
        @title_uri = spec["titleUri"]
        @filter = spec.fetch("filter", false)
        @search = !!spec["search"]
      end

      def filtered?
        !!filter
      end

      def search?
        search
      end
    end

    class ValuePropDef < Common
      attr_reader :as, :nullable, :strict

      def initialize(spec)
        super
        @as = spec["as"]
        @nullable = spec["nullable"] == true
        @strict = spec["strict"] == true
      end

      def type = "value"
      def uri = nil

      def text_for_value(value, _lang = nil)
        value.nil? ? nil : Coerce.stringify(value)
      end
    end

    class VocabPropDef < Common
      attr_reader :uri, :i18n_vocab

      def initialize(spec, i18n_vocab)
        super(spec)
        @uri = spec["uri"]
        @i18n_vocab = i18n_vocab
      end

      def type = "vocab"

      def localised_vocab_def(lang)
        i18n_vocab[lang] or raise Error, "no terms defined for language code '#{lang}' in vocab '#{uri}'"
      end

      def text_for_value(value, lang = nil)
        raise Error, "no language code provided for vocab '#{uri}'" if lang.nil?
        return localised_vocab_def(lang)["terms"][value] if value.is_a?(String)
        ""
      end
    end

    class MultiPropDef < Common
      attr_reader :of

      def initialize(spec, of)
        super(spec)
        @of = of
      end

      def type = "multi"

      def uri
        of.type == "vocab" ? of.uri : nil
      end

      def i18n_vocab
        of.is_a?(VocabPropDef) ? of.i18n_vocab : nil
      end

      def text_for_value(value, lang = nil)
        return [] unless value.is_a?(Array)
        value.map { |v| Coerce.stringify(of.text_for_value(v, lang)) }
      end
    end
  end
end
