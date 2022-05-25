# Definitions in common.mk can be overridden here

###########################################
# Where are the initial CSV files located?
SRC_CSV_DIR := co-ops-uk-csv-data/

###########################################
# Components of the URIs used in this dataset:
# Generated URIs will datrt with: $(URI_SCHEME)://$(URI_HOST)/$(URI_PATH_PREFIX)
URI_SCHEME := https
URI_HOST := lod.coop
URI_PATH_PREFIX := coops-uk

###########################################
# To where are the Linked Data to be deployed?
# Note that content negotiation needs to be set up so that HTTP requests made to URIs (configured above)
# can be dereferenced to the deployed RDF and HTML files (configured below).
# The value of DEPLOYMENT_SERVER should be the name of a host set up in an ssh config file. 
#     (See http://nerderati.com/2011/03/17/simplify-your-life-with-an-ssh-config-file/)
DEPLOYMENT_SERVER ?= prod-1
ESSGLOBAL_URI	 := https://w3id.solidarityeconomy.coop/essglobal/V2a/

# The directory on the deployment server where the RDF and HTML is to be deployed:
DEPLOYMENT_WEBROOT := /var/www/vhosts/data.solidarityeconomy.coop/www/

# Flags used with the rsync command:
# WARNING: --delete will delete files on the server that don't correspond
#         to files in the local directory of generated RDF and HTML:
DEPLOYMENT_RSYNC_FLAGS := --delete

###########################################
# Set up the triplestore:
#
# virtuoso server name, typically this is configured in ~/.ssh/config:
VIRTUOSO_SERVER := prod-1
# Directory on virtuoso server which has been configured (DirsAllowed in virtuoso.ini)
# ready for Bulk data loading:
VIRTUOSO_ROOT_DATA_DIR := /var/tmp/virtuoso/BulkLoading/
SPARQL_ENDPOINT := http://prod-1.solidarityeconomy.coop:8890/sparql
