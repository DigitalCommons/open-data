require 'se_open_data/csv/schema'

module SeOpenData
  module CSV
    
    # Defines various Solidarity Economy schemas
    module Schemas

      # This defines the the minumum lime-survey CSV schema fields
      module LimeSurveyCore
        Versions = [
          SeOpenData::CSV::Schema.new(
            id: :limesurveycore,
            name: "LimeSurvey Core",
            version: 20201006,
            comment: 'Common fields required by SeOpenData::CSV::Converter::Generic',
            primary_key: [:id],
            fields: [
              {id: :id,
               header: 'id',
               desc: 'A unique identifier for this initiative',
               comment: '',
              },
              {id: :name,
               header: 'name',
               desc: '',
               comment: '',
              },
              {id: :description,
               header: 'description',
               desc: '',
               comment: '',
              },
              {id: :address_a,
               header: 'address[a]',
               desc: '',
               comment: '',
              },
              {id: :address_b,
               header: 'address[b]',
               desc: '',
               comment: '',
              },
              {id: :address_c,
               header: 'address[c]',
               desc: '',
               comment: '',
              },
              {id: :locality,
               header: 'address[d]',
               desc: '',
               comment: '',
              },
              {id: :postcode,
               header: 'address[e]',
               desc: '',
               comment: '',
              },
              {id: :location,
               header: 'location',
               desc: '',
               comment: '',
              },
              {id: :email,
               header: 'email',
               desc: '',
               comment: '',
              },
              {id: :phone,
               header: 'phone',
               desc: '',
               comment: '',
              },
              {id: :website,
               header: 'website',
               desc: '',
               comment: '',
              },
              {id: :facebook,
               header: 'facebook',
               desc: '',
               comment: '',
              },
              {id: :twitter,
               header: 'twitter',
               desc: '',
               comment: '',
              },
              {id: :activity,
               header: 'activity',
               desc: '',
               comment: '',
              },
              {id: :approved,
               header: 'approved',
               desc: 'Will be "Yes" if this initiative has been validated and approved by an admin',
               comment: 'Initiatives should only be imported if they are approved.',
              },
              {id: :community_group,
               header: 'structure[SQ001]',
               desc: '',
               comment: '',
              },
              {id: :non_profit,
               header: 'structure[SQ002]',
               desc: '',
               comment: '',
              },
              {id: :social_enterprise,
               header: 'structure[SQ003]',
               desc: '',
               comment: '',
              },
              {id: :charity,
               header: 'structure[SQ004]',
               desc: '',
               comment: '',
              },
              {id: :company,
               header: 'structure[SQ005]',
               desc: '',
               comment: '',
              },
              {id: :workers_coop,
               header: 'structure[SQ006]',
               desc: '',
               comment: '',
              },
              {id: :housing_coop,
               header: 'structure[SQ007]',
               desc: '',
               comment: '',
              },
              {id: :consumer_coop,
               header: 'structure[SQ008]',
               desc: '',
               comment: '',
              },
              {id: :producer_coop,
               header: 'structure[SQ009]',
               desc: '',
               comment: '',
              },
              {id: :stakeholder_coop,
               header: 'structure[SQ010]',
               desc: '',
               comment: '',
              },
              {id: :community_interest_company,
               header: 'structure[SQ011]',
               desc: '',
               comment: '',
              },
              {id: :community_benefit_society,
               header: 'structure[SQ012]',
               desc: '',
               comment: '',
              },
              {id: :arts,
               header: 'secondaryActivities[SQ002]',
               desc: '',
               comment: '',
              },
              {id: :campaigning,
               header: 'secondaryActivities[SQ003]',
               desc: '',
               comment: '',
              },
              {id: :community,
               header: 'secondaryActivities[SQ004]',
               desc: '',
               comment: '',
              },
              {id: :education,
               header: 'secondaryActivities[SQ005]',
               desc: '',
               comment: '',
              },
              {id: :energy,
               header: 'secondaryActivities[SQ006]',
               desc: '',
               comment: '',
              },
              {id: :food,
               header: 'secondaryActivities[SQ007]',
               desc: '',
               comment: '',
              },
              {id: :goods_services,
               header: 'secondaryActivities[SQ008]',
               desc: '',
               comment: '',
              },
              {id: :health,
               header: 'secondaryActivities[SQ009]',
               desc: '',
               comment: '',
              },
              {id: :housing,
               header: 'secondaryActivities[SQ010]',
               desc: '',
               comment: '',
              },
              {id: :money,
               header: 'secondaryActivities[SQ011]',
               desc: '',
               comment: '',
              },
              {id: :nature,
               header: 'secondaryActivities[SQ012]',
               desc: '',
               comment: '',
              },
              {id: :reuse,
               header: 'secondaryActivities[SQ013]',
               desc: '',
               comment: '',
              },
              # {id: :agriculture,
              #  header: 'secondaryActivities[SQ014]',
              #  desc: '',
              #  comment: '',
              # },
              # {id: :industry,
              #  header: 'secondaryActivities[SQ015]',
              #  desc: '',
              #  comment: '',
              # },
              # {id: :utilities,
              #  header: 'secondaryActivities[SQ016]',
              #  desc: '',
              #  comment: '',
              # },
              # {id: :transport,
              #  header: 'secondaryActivities[SQ017]',
              #  desc: '',
              #  comment: '',
              # },
            ]
          )
        ]

        # Shortcut alias for the latest schema
        Latest = Versions[-1]
      end
      
      # Defines the schema versions in order of creation.
      #
      # Note, schema field IDs are used in the code and should not be
      # changed for any given schema (otherwise code may break).
      # They may be changed between versions.
      #
      Versions = [
        SeOpenData::CSV::Schema.new(
          id: :sse_initiatives,
          name: "Solidarity Economy Initiatives",
          version: 1,
          description: <<-HERE,

## Geographic coordinates

`Latitude` and `Longitude` are for the exact geolocation of the SSE
initiative, if it is known.

If only a postcode or an address is known, use the `Geo Container *`
fields.

Often, we don't know the exact lat/long of an SSE initiative, but we
know about a geographic container which has a known lat/long.  The
most common example of this is the postcode as a geographic container.

Note that the utility `bin/csv/standard/add-postcode-lat-long.rb` will
populate these 3 fields based on the value of the `Postcode`, so don't
do it manually!  This is used, for example, in the toolchain for
generating the co-ops-uk 2017 RDF.

## Sub-fields

Sometimes a single column can take values that are in fact a list.  So
we need to know the character used to separate the items in the list.
For example, in the legal_form column, we might have an initiative
that is both a 'Cooperative' and a 'Company', the cell would then have
the value "Cooperative;Company"

HERE
          comment: 'Initial version',
          primary_key: [:id],
          fields: [
            {id: :id,
             header: 'Identifier',
             desc: 'A unique identifier for this initiative',
             comment: <<-HERE
As a consequence of needing to name generated static files with these 
identifiers, which will then be published by a web server, they must be
both a) valid as a portion of a file-name on the (typically, Unix) 
host's file system, and b) as a URI segment as defined by RFC3986 
<https://tools.ietf.org/html/rfc3986#section-3.3>
HERE
            },
            {id: :name,
             header: 'Name',
             desc: '',
             comment: '',
            },
            {id: :description,
             header: 'Description',
             desc: '',
             comment: '',
            },
            {id: :organisational_structure,
             header: 'Organisational Structure',
             desc: '',
             comment: <<-HERE,
This was known as legal_form. The allowed values are taken from the
ESSGLOBAL specification.
HERE
            },
            {id: :primary_activity,
             header: 'Primary Activity',
             desc: '',
             comment: '',
            },
            {id: :activities,
             header: 'Activities',
             desc: '',
             comment: '',
            },
            {id: :street_address,
             header: 'Street Address',
             desc: '',
             comment: '',
            },
            {id: :locality,
             header: 'Locality',
             desc: '',
             comment: '',
            },
            {id: :region,
             header: 'Region',
             desc: '',
             comment: '',
            },
            {id: :postcode,
             header: 'Postcode',
             desc: '',
             comment: '',
            },
            {id: :country_name,
             header: 'Country Name',
             desc: '',
             comment: '',
            },
            {id: :homepage,
             header: 'Website',
             desc: '',
             comment: '',
            },
            {id: :phone,
             header: 'Phone',
             desc: '',
             comment: '',
            },
            {id: :email,
             header: 'Email',
             desc: '',
             comment: '',
            },
            {id: :twitter,
             header: 'Twitter',
             desc: '',
             comment: '',
            },
            {id: :facebook,
             header: 'Facebook',
             desc: '',
             comment: '',
            },
            {id: :companies_house_number,
             header: 'Companies House Number',
             desc: '',
             comment: '',
            },
            {id: :latitude,
             header: 'Latitude',
             desc: '',
             comment: '',
            },
            {id: :longitude,
             header: 'Longitude',
             desc: '',
             comment: '',
            },
            {id: :geocontainer,
             header: 'Geo Container',
             desc: '',
             comment: '',
            },
            {id: :geocontainer_lat,
             header: 'Geo Container Latitude',
             desc: '',
             comment: '',
            },
            {id: :geocontainer_lon,
             header: 'Geo Container Longitude',
             desc: '',
             comment: '',
            },
          ]        
        ),
        SeOpenData::CSV::Schema.new(
          id: :sse_initiatives,
          name: "Solidarity Economy Initiatives",
          version: 2,
          description: <<-HERE,

## Geographic coordinates

`Latitude` and `Longitude` are for the exact geolocation of the SSE
initiative, if it is known.

If only a postcode or an address is known, use the `Geo Container *`
fields.

Often, we don't know the exact lat/long of an SSE initiative, but we
know about a geographic container which has a known lat/long.  The
most common example of this is the postcode as a geographic container.

Note that the utility `bin/csv/standard/add-postcode-lat-long.rb` will
populate these 3 fields based on the value of the `Postcode`, so don't
do it manually!  This is used, for example, in the toolchain for
generating the co-ops-uk 2017 RDF.

## Sub-fields

Sometimes a single column can take values that are in fact a list.  So
we need to know the character used to separate the items in the list.
For example, in the legal_form column, we might have an initiative
that is both a 'Cooperative' and a 'Company', the cell would then have
the value "Cooperative;Company"

HERE
          comment: 'Added "Qualifiers" field',
          primary_key: [:id],
          fields: [
            {id: :id,
             header: 'Identifier',
             desc: 'A unique identifier for this initiative',
             comment: <<-HERE
As a consequence of needing to name generated static files with these 
identifiers, which will then be published by a web server, they must be
both a) valid as a portion of a file-name on the (typically, Unix) 
host's file system, and b) as a URI segment as defined by RFC3986 
<https://tools.ietf.org/html/rfc3986#section-3.3>
HERE
            },
            {id: :name,
             header: 'Name',
             desc: '',
             comment: '',
            },
            {id: :description,
             header: 'Description',
             desc: '',
             comment: '',
            },
            {id: :organisational_structure,
             header: 'Organisational Structure',
             desc: '',
             comment: <<-HERE,
This was known as legal_form. The allowed values are taken from the
ESSGLOBAL specification.
HERE
            },
            {id: :primary_activity,
             header: 'Primary Activity',
             desc: '',
             comment: '',
            },
            {id: :activities,
             header: 'Activities',
             desc: '',
             comment: '',
            },
            {id: :street_address,
             header: 'Street Address',
             desc: '',
             comment: '',
            },
            {id: :locality,
             header: 'Locality',
             desc: '',
             comment: '',
            },
            {id: :region,
             header: 'Region',
             desc: '',
             comment: '',
            },
            {id: :postcode,
             header: 'Postcode',
             desc: '',
             comment: '',
            },
            {id: :country_name,
             header: 'Country Name',
             desc: '',
             comment: '',
            },
            {id: :homepage,
             header: 'Website',
             desc: '',
             comment: '',
            },
            {id: :phone,
             header: 'Phone',
             desc: '',
             comment: '',
            },
            {id: :email,
             header: 'Email',
             desc: '',
             comment: '',
            },
            {id: :twitter,
             header: 'Twitter',
             desc: '',
             comment: '',
            },
            {id: :facebook,
             header: 'Facebook',
             desc: '',
             comment: '',
            },
            {id: :companies_house_number,
             header: 'Companies House Number',
             desc: '',
             comment: '',
            },
            {id: :qualifiers,
             header: 'Qualifiers',
             desc: '',
             comment: '',
            },
            {id: :latitude,
             header: 'Latitude',
             desc: '',
             comment: '',
            },
            {id: :longitude,
             header: 'Longitude',
             desc: '',
             comment: '',
            },
            {id: :geocontainer,
             header: 'Geo Container',
             desc: '',
             comment: '',
            },
            {id: :geocontainer_lat,
             header: 'Geo Container Latitude',
             desc: '',
             comment: '',
            },
            {id: :geocontainer_lon,
             header: 'Geo Container Longitude',
             desc: '',
             comment: '',
            },
          ]        
        ),
        
        SeOpenData::CSV::Schema.new(
          id: :sse_initiatives,
          name: "Solidarity Economy Initiatives",
          version: 3,
          description: <<-HERE,

## Geographic coordinates

`Latitude` and `Longitude` are for the exact geolocation of the SSE
initiative, if it is known.

If only a postcode or an address is known, use the `Geo Container *`
fields.

Often, we don't know the exact lat/long of an SSE initiative, but we
know about a geographic container which has a known lat/long.  The
most common example of this is the postcode as a geographic container.

Note that the utility `bin/csv/standard/add-postcode-lat-long.rb` will
populate these 3 fields based on the value of the `Postcode`, so don't
do it manually!  This is used, for example, in the toolchain for
generating the co-ops-uk 2017 RDF.

## Sub-fields

Sometimes a single column can take values that are in fact a list.  So
we need to know the character used to separate the items in the list.
For example, in the legal_form column, we might have an initiative
that is both a 'Cooperative' and a 'Company', the cell would then have
the value "Cooperative;Company"

HERE
          comment: 'Added "Membership Type" field',
          primary_key: [:id],
          fields: [
            {id: :id,
             header: 'Identifier',
             desc: 'A unique identifier for this initiative',
             comment: <<-HERE
As a consequence of needing to name generated static files with these 
identifiers, which will then be published by a web server, they must be
both a) valid as a portion of a file-name on the (typically, Unix) 
host's file system, and b) as a URI segment as defined by RFC3986 
<https://tools.ietf.org/html/rfc3986#section-3.3>
HERE
            },
            {id: :name,
             header: 'Name',
             desc: '',
             comment: '',
            },
            {id: :description,
             header: 'Description',
             desc: '',
             comment: '',
            },
            {id: :organisational_structure,
             header: 'Organisational Structure',
             desc: '',
             comment: <<-HERE,
This was known as legal_form. The allowed values are taken from the
ESSGLOBAL specification.
HERE
            },
            {id: :primary_activity,
             header: 'Primary Activity',
             desc: '',
             comment: '',
            },
            {id: :activities,
             header: 'Activities',
             desc: '',
             comment: '',
            },
            {id: :street_address,
             header: 'Street Address',
             desc: '',
             comment: '',
            },
            {id: :locality,
             header: 'Locality',
             desc: '',
             comment: '',
            },
            {id: :region,
             header: 'Region',
             desc: '',
             comment: '',
            },
            {id: :postcode,
             header: 'Postcode',
             desc: '',
             comment: '',
            },
            {id: :country_name,
             header: 'Country Name',
             desc: '',
             comment: '',
            },
            {id: :homepage,
             header: 'Website',
             desc: '',
             comment: '',
            },
            {id: :phone,
             header: 'Phone',
             desc: '',
             comment: '',
            },
            {id: :email,
             header: 'Email',
             desc: '',
             comment: '',
            },
            {id: :twitter,
             header: 'Twitter',
             desc: '',
             comment: '',
            },
            {id: :facebook,
             header: 'Facebook',
             desc: '',
             comment: '',
            },
            {id: :companies_house_number,
             header: 'Companies House Number',
             desc: '',
             comment: '',
            },
            {id: :qualifiers,
             header: 'Qualifiers',
             desc: '',
             comment: '',
            },
            {id: :base_membership_type,
             header: 'Membership Type',
             desc: '',
             comment: '',
            },
            {id: :latitude,
             header: 'Latitude',
             desc: '',
             comment: '',
            },
            {id: :longitude,
             header: 'Longitude',
             desc: '',
             comment: '',
            },
            {id: :geocontainer,
             header: 'Geo Container',
             desc: '',
             comment: '',
            },
            {id: :geocontainer_lat,
             header: 'Geo Container Latitude',
             desc: '',
             comment: '',
            },
            {id: :geocontainer_lon,
             header: 'Geo Container Longitude',
             desc: '',
             comment: '',
            },
          ]        
        ),
        
        SeOpenData::CSV::Schema.new(
          id: :sse_initiatives,
          name: "Solidarity Economy Initiatives",
          version: 4,
          description: <<-HERE,

## Terms or identifiers

Where a field is defined as a term from a SKOS vocabulary or other
identifier, the namespace varies with the dataset. Strictly this
should be explicitly defined, but is outside the scope of this schema.
Full linked-data URIs can be used, which should be globally unique, or
URIs with prefixes denoted by some abbreviation, delimited by a colon,
or identifiers in some base namespace, as commonly used in TTL. If the
latter, the base namespace and prefixes should be defined elsewhere
such that the full globally-unique URI can be inferred.

This means that identifiers used prior to the tighening-up of this
schema definition are mostly still valid if we define the base
namespace appropriately. The difficulty is when multiple namespaces
are allowed - such as mixing country identifiers with ICA regions, if
they require different prefixes to be inferred. But this still works
if an over-arching vocabulary is defined, which can then be declared
the base namespace. A small tweak would be to declare prefixes.

## Geographic coordinates

`Latitude` and `Longitude` are for the exact geolocation of the SSE
initiative, if it is known.

If only a postcode or an address is known, use the `Geo Container *`
fields.

Often, we don't know the exact lat/long of an SSE initiative, but we
know about a geographic container which has a known lat/long.  The
most common example of this is the postcode as a geographic container.

Note that the utility `bin/csv/standard/add-postcode-lat-long.rb` will
populate these 3 fields based on the value of the `Postcode`, so don't
do it manually!  This is used, for example, in the toolchain for
generating the co-ops-uk 2017 RDF.

## Sub-fields

Sometimes a single column can take values that are in fact a list.  So
we need to know the character used to separate the items in the list.
For example, in the legal_form column, we might have an initiative
that is both a 'Cooperative' and a 'Company', the cell would then have
the value "Cooperative;Company". This of course assumes that the
delimited identifiers do not contain any semi-colons themselves. There
is no current provision for cases where this is not true.

HERE
          comment: 'Added "territory_id" field, redefined "country_name" as "country_id',
          primary_key: [:id],
          fields: [
            {id: :id,
             header: 'Identifier',
             desc: 'A unique identifier for this initiative',
             comment: <<-HERE
As a consequence of needing to name generated static files with these 
identifiers, which will then be published by a web server, they must be
both a) valid as a portion of a file-name on the (typically, Unix) 
host's file system, and b) as a URI segment as defined by RFC3986 
<https://tools.ietf.org/html/rfc3986#section-3.3>
HERE
            },
            {id: :name,
             header: 'Name',
             desc: 'The name of the initiative, as UTF-8 plain text',
             comment: 'Typically in English, but this depends on the context',
            },
            {id: :description,
             header: 'Description',
             desc: 'A description of the initiative, as a UTF-8 encoded HTML fragment',
             comment: <<-HERE,
Typically in English, but this depends on the context. Hopefully not with malicious content
which could compromise security if embedded in a webpage (such as phishing links or 
scripts), but this should validated and not be assumed blindly to be safe.
HERE
            },
            {id: :organisational_structure,
             header: 'Organisational Structure',
             desc: <<-HERE,
The initiative's category of organisational structure. Allowed values are 
single term URIs from a relevant vocabulary.
HERE
             comment: <<-HERE,
This was known as legal_form. 
HERE
            },
            {id: :primary_activity,
             header: 'Primary Activity',
             desc: <<-HERE,
The main category of actitivity executed by the initiative. Allowed values are 
single terms from a relevant vocabulary.
HERE
             comment: '',
            },
            {id: :activities,
             header: 'Activities',
             desc: <<-HERE,
Any additional categories of actitivity executed by the initiative. Allowed values are 
zero or more terms from a relevant vocabulary, separated by semi-colons.
HERE
             comment: '',
            },
            {id: :street_address,
             header: 'Street Address',
             desc: <<-HERE,
An optional street name and postbox number (where applicable) for the main address of
the initiative.
HERE
             comment: '',
            },
            {id: :locality,
             header: 'Locality',
             desc: <<-HERE,
An optional sub-regional locality (e.g. town, city, parish) for the main address of the initiative.
Typically a textual name, in the local language, UTF-8 encoded.
HERE
             comment: '',
            },
            {id: :region,
             header: 'Region',
             desc: <<-HERE,
An optional sub-national region for the main address of the initiative.
Typically a textual name, in the local language, UTF-8 encoded.
HERE
             comment: '',
            },
            {id: :postcode,
             header: 'Postcode',
             desc: <<-HERE,
An optional postcode or zipcode, applicable in the context of the main address.
HERE
             comment: '',
            },
            {id: :country_id,
             header: 'Country ID',
             desc: <<-HERE,
An optional country identifier for the main address.
Should be an uppercase ISO-3166-1 two-letter country code.
HERE
             comment: '',
            },
            {id: :territory_id,
             header: 'Territory ID',
             desc: <<-HERE ,
Indicates the territory in which the initiative operates. Values
should be a term from a relevant vocabulary, or other identifier.
HERE
             comment: <<-HERE,
There are ESSGLOBAL SKOS vocabs for the ISO and ICA region/super-region identifiers
HERE
            },
            {id: :homepage,
             header: 'Website',
             desc: "An optional valid URL for the initiative's main web page",
             comment: '',
            },
            {id: :phone,
             header: 'Phone',
             desc: "An optional valid contact telephone number for the initiative",
             comment: 'Historically, if not international, these have been UK phone numbers.',
            },
            {id: :email,
             header: 'Email',
             desc: "An optional valid contact email address for the initiative",
             comment: '',
            },
            {id: :twitter,
             header: 'Twitter',
             desc: "An optional valid URL for the initiative's main Twitter account",
             comment: '',
            },
            {id: :facebook,
             header: 'Facebook',
             desc: <<-HERE,
An optional valid path for the initiative's main Facebook presence. Should be
prefixed with `http://facebook.com/` to get the actual URL.
HERE
             comment: <<-HERE
Historically, this can also be an actual URL, but this can cause problems
because of the prior assumption it is not.
HERE
            },
            {id: :companies_house_number,
             header: 'Companies House Number',
             desc: 'A UK Companies House Number, when applicable. Optional.',
             comment: '',
            },
            {id: :qualifiers,
             header: 'Qualifiers',
             desc: <<-HERE,
Additional qualifiers on the initiative. Allowed values are 
zero or more term URIs from a relevant vocabulary, separated by semi-colons.
HERE
             comment: '',
            },
            {id: :base_membership_type,
             header: 'Membership Type',
             desc: <<-HERE,
The membership type of the initiative. Allowed values are 
zero or one term URIs from a relevant vocabulary.
HERE
             comment: '',
            },
            {id: :latitude,
             header: 'Latitude',
             desc: <<-HERE,
An optional latitudinal coordinate of the initiative's main address, if known.
A floating point number.
HERE
             comment: '',
            },
            {id: :longitude,
             header: 'Longitude',
             desc: <<-HERE,
An optional longitudinal coordinage of the initiative's main address, if known.
A floating point number.
HERE
             comment: '',
            },
            {id: :geocontainer,
             header: 'Geo Container',
             desc: <<-HERE,
An optional identifier indicating a geographical region containing the initiative's
main address, if known.
HERE
             comment: '',
            },
            {id: :geocontainer_lat,
             header: 'Geo Container Latitude',
             desc: <<-HERE,
An optional latitudinal coordinate of the initiative's main address, when
inferred from the address fields. A floating point number.
HERE
             comment: '',
            },
            {id: :geocontainer_lon,
             header: 'Geo Container Longitude',
             desc: <<-HERE,
An optional longitudinal coordinate of the initiative's main address, when
inferred from the address fields. A floating point number.
HERE
             comment: '',
            },
          ]        
        ),
      ]
      
      # Shortcut alias for the latest schema
      Latest = Versions[-1]
    end
  end
end
