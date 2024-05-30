#!/bin/bash
#
# NAME
#
# generate-db2.sh
#
#
# SYNOPSIS
#
# Downloads, sanitises, and combines DotCoop, NCBA, ICA and Coops-UK
# organisational lists into one global list. A best effort operation,
# linking them by their .coop domain registrations.
#
#
# USAGE
# 
# Define the parameters in `defs.sh`, then run the `generate-db2.sh` script with no options.
#
# An intermediate Sqlite3 database will be constructed.  This will
# contain a table `map_data` which defines what will be used by the
# consuming Mykomap.
#
# defs.sh should define the following environment variables:
#
# - DC_URL: an URL to a 'standard Mykomap schema' CSV file containing the DotCoop organisation data 
# - DC_CSV: the name of a file to download that to
# - DC_TB: the name of a database table to import that to
# - DC_FK: the name of the primary key field of that table.
# - ICA_URL, ICA_CSV, ICA_TB, ICA_FK: ditto, but for the ICA data
# - NCBA_URL, NCBA_CSV, NCBA_TB, NCBA_FK,
# - CUK_URL, CUK_CSV, CUK_TB, CUK_FK
# - DB: the filename of the Sqlite3 database to create
# - OUT_CSV: the name of a CSV to dump the `map_data` table to
#
# A CSV can be dumped from this view, but currently is not done by this script.
#
#
# DISCUSSION
#
# Aim: select each org from all datasets once only, and combine NCBA,
# DC and ICA information where a correspondance can be established
# based on the .coop domains.
#
# Note: all .coop domains can (should!?) be guaranteed to be linked to
# a single organisation. (This is only approximately true! e.g. We can
# see the re-use of APEX org .coop domains in the CUK dataset.)
#
# Note: the DotCoop database is being curated to try and identify
# unique organisations, but because of the way registries work, may
# not always correctly identify registrants that are the same
# organisation.
#
# Note: sometimes the DC table is inconsistent with the NCBA and ICA
# domains! So you may find .coop domains in the latter two which aren't in
# the former.
#
# Assumptions:
# - A .coop domain can only be linked to one organisation
# - Non .coop domains may be linked with one *or more* organisations
# - There are no DC organisations included which are not linked to a .coop domain
# - But more generally, an organisation *can* be linked to zero (or more) .coop domains
#
# General procedure: somewhat like deduplicating set members in a Venn diagram,
# we take one set, then add in the others, whilst removing the overlaps. The overlaps
# get incrementally broader in each step.
#
#     all_orgs = dc + (ncba - dc) + (ica - dc - ncba)
#
# Partially translating into SQL logic:
#
# 1) Select DC organisations
#    [ left join `ica` and `ncba` to `dc_domains` table where they have a .coop domain ]
# 2) Add NCBA organisations without a .coop domain
#    [ left join `dc_domains` to `ncba` on the domain, select those with no .coop domain ] 
# 3) Add ICA organisations without .coop domain or NCBA links
#    [ left join `dc_domains` to `ica` on the domain, select those with no .coop domain ]
#    [ we cannot identify overlaps between ICA and NCBA currently ]
#
# Tables and their occupancy expectations:
# - dc, ncba, ica and cuk: have all the organisations known to each of those datasets
#   once, plus information about any domains they are associated with (via URLs or otherwise,
#   although these may be to non .coop and/or shared domains in some cases; the former are
#   not useful and ignored, the latter are problematic and also ignored, for now, for lack of any
#   means of resolution)
# - domains: has all the domains from all datasets, zero or more times (FIXME not used)
# - domain_freq: has all the domains from all datasets just once, plus null, with
#   their frequency of appearance in the other datasets. (Null here is for organisations with no
#   domain associated)
# - icaid_to_dcid: maps ICA orgs to DC orgs. One row max for each ICA org where a link exists.
# - icaid_to_dcid: maps NCBA orgs to DC orgs. One row max for each NCBA org where a link exists.
# - dc_orgs: has all the DC organisations, with links to NCBA and ICA where found
# - ncba_not_dc_orgs: has all the NCBA organisations which aren't linked in the dc_orgs table
# - ica_not_dc_orgs: has all the ICA organisations which aren't linked in the dc_orgs table
#   (and are assumed not to be in the ncba_not_dc_orgs table, but we have no way of inferring)
# - all_orgs: one row for each organisation - a unification of the previous three tables.
# - map_data: ditto, but in the form needed for the map CSV, with a unique ID field
#

set -vx
set -e

. defs.sh

mkdir -p $OUTDIR

# Safety first - don't blindly overwrite database if it exists
if [ -e $DB ]; then
    read -p "Overwrite $DB? [Y/N]" response
    if [[ "$response" == "Y" ]]; then
	rm -f $DB;
    else
	echo "Stopping."
	exit 1;
    fi
fi

curl -f $DC_URL >$DC_CSV
curl -f $ICA_URL >$ICA_CSV
curl -f $NCBA_URL >$NCBA_CSV
curl -f $CUK_URL >$CUK_CSV


# --blanks is important otherwise 'NA', 'N/A', 'none' or 'null' -> null!
csvsql --db sqlite:///$DB --tables $DC_TB --blanks --no-constraints --insert $DC_CSV
csvsql --db sqlite:///$DB --tables $ICA_TB --blanks --no-constraints --insert $ICA_CSV
csvsql --db sqlite:///$DB --tables $NCBA_TB --blanks --no-constraints --insert $NCBA_CSV
csvsql --db sqlite:///$DB --tables $CUK_TB --blanks --no-constraints --insert $CUK_CSV

# Add Domains field to $DC_TB
sqlite3 $DB "alter table $DC_TB add column Domains VARCHAR"

# For ICA, CUK: Copy Website URLs as Domain
for TB in $ICA_TB $CUK_TB; do
    # Add Domain field
    sqlite3 $DB "alter table $TB add column Domain VARCHAR"
    sqlite3 $DB "update $TB set Domain = Website"
done

# For ICA, NCBA - make the Identifier field an integer (not a real)
# Otherwise, sqlite will insert a trailing '.0' on export
for TB in $ICA_TB $NCBA_TB $CUK_TB; do
    sqlite3 $DB "alter table $TB add column temp INTEGER"
    sqlite3 $DB "update $TB set temp = Identifier"
    sqlite3 $DB "alter table $TB drop column Identifier"
    sqlite3 $DB "alter table $TB rename column temp to Identifier"
done

# For ICA, NCBA, CUK: clean them up into bare domains
for TB in $ICA_TB $NCBA_TB $CUK_TB; do
    # Make add a unique index on Identifier
    sqlite3 $DB "alter table $TB add column temp VARCHAR NOT NULL DEFAULT '-'"
    sqlite3 $DB "update $TB set temp = Identifier"
    sqlite3 $DB "alter table $TB drop column Identifier"
    sqlite3 $DB "alter table $TB rename column temp to Identifier"
    sqlite3 $DB "create unique index ${TB}Identifier on $TB (Identifier)"
    
    sqlite3 $DB "update $TB set Domain = lower(Domain)"
    sqlite3 $DB "update $TB set Domain = replace(Domain, 'http://', '')"
    sqlite3 $DB "update $TB set Domain = replace(Domain, 'https://', '')"
    sqlite3 $DB "update $TB set Domain = replace(Domain, 'http://', '')"
    sqlite3 $DB "update $TB set Domain = substr(Domain, 0, instr(Domain||'/','/'));" # remove paths
    sqlite3 $DB "update $TB set Domain = substr(Domain, instr(Domain, '.')+1) where Domain like '%.%.coop'"; # remove subdomains - well, one level.
    sqlite3 $DB "update $TB set Domain = substr(Domain, instr(Domain, '.')+1) where Domain like '%.%.coop'"; # second
    sqlite3 $DB "update $TB set Domain = substr(Domain, instr(Domain, '.')+1) where Domain like '%.%.coop'"; # third?
    # Remove any remaining www. subdomains
    sqlite3 $DB "update $TB set Domain = substr(Domain, instr(Domain, '.')+1) where Domain like 'www.%.%'"; # third?
done

# Cleanup for all datasets
for TB in $ICA_TB $NCBA_TB $DC_TB $CUK_TB; do
    # Replace empty strings which represent nulls with nulls
    sqlite3 "$DB" "select f.name from sqlite_master t, pragma_table_info((t.name)) f on t.name <> f.name where t.name = '$TB'" |
	while IFS=$'\n' read -rs FIELD; do
	    sqlite3 $DB "update $TB set \`$FIELD\` = NULL where \`$FIELD\` = '';"
	done
		   
    # Any orgs with lat/lng 0,0 should be set to null (this is a problem with ICA data at least,
    # which may need fixing properly upstream
    sqlite3 $DB "update $TB set Latitude = null, Longitude = null where Latitude = 0 and Longitude = 0;"

    # insert a slug field identifying the dataset
    sqlite3 $DB "alter table $TB add column slug VARCHAR"
    sqlite3 $DB "update $TB set slug = '$TB'"    
done

# Likewise for DC, copy Website into Domains and clean up (although less cleaning needed)
sqlite3 $DB "update $DC_TB set Domains = lower(Website)"
sqlite3 $DB "update $DC_TB set Domains = replace(Domains, 'http://', '')"
sqlite3 $DB "update $DC_TB set Domains = replace(Domains, 'https://', '')"

# Convert adhoc to vocab fields...?

# Compile lists of DC domains and identifiers
sqlite3  -csv $DB "select Identifier, Domains from $DC_TB" | \
    perl -nE 'chomp; ($id,$d) = split /,/; @d = split /;/, $d; say "$_,$id" for @d' >$OUTDIR/$DC_TB-domains.csv
#sqlite3  -csv $DB "select Identifier,Domain from $ICA_TB" >>$ICA_TB-domains.csv
#sqlite3  -csv $DB "select Identifier,Domain from $NCBA_TB" >>$NCBA_TB-domains.csv

# Insert the DC domains back as a new 1:* table
#for tb in $DC_TB $ICA_TB $NCBA_TB; do 
(printf "domain,${DC_FK}\n";
 cat $OUTDIR/$DC_TB-domains.csv) | \
    csvsql --db sqlite:///$DB --tables domains --insert --no-constraints -
#done

# Add $ICA_FK and $NCBA_FK fields, and indexes on them
for FK in $ICA_FK $NCBA_FK $CUK_FK; do 
    sqlite3 $DB "alter table domains add column $FK VARCHAR"
    sqlite3 $DB "create unique index $FK on domains ($FK)"
done

# and the domains field ($DC_FK there already)
sqlite3 $DB "create index domain on domains (domain)"
sqlite3 $DB "create index $DC_FK on domains ($DC_FK)"

######################################################################
# At this point we have sanitised the input data and normalised and
# separated out the linking domains.
#
# Next we can start combining them. We need to create a unifying grand
# list of organisations, with foreign key links back to the original
# organisation tables.

# Before we add more domains from other datasets, create a table
# linking all the .coop domains to their DC registrant orgs.
sqlite3 $DB "create table dc_domains as select domain, dcid from domains;"


# Create foreign refs from domains to $NCBA_TB, $ICA_TB and $CUK_TB
# tables based on Domains/Domain matches
sqlite3 $DB "insert into domains (domain,$ICA_FK) select $ICA_TB.Domain,$ICA_TB.Identifier from $ICA_TB;"
sqlite3 $DB "insert into domains (domain,$NCBA_FK) select $NCBA_TB.Domain,$NCBA_TB.Identifier from $NCBA_TB;"
sqlite3 $DB "insert into domains (domain,$CUK_FK) select $CUK_TB.Domain,$CUK_TB.Identifier from $CUK_TB;"

# Create a frequency table listing unique domains found and the number
# of times they appear in DC, ICA and NCBA databases. This is not used
# directly later, but is useful for analysing the data - notably
# knowing when assumptions about domains are not valid!
sqlite3 $DB "create table domain_freq as select domain, count(dcid) as dc, count(icaid) as ica, count(ncbaid) as ncba, count(cukid) as cuk from domains group by domain;"



# Define a view which links those NCBA organisations which have a .coop
# website to a DC organisation, via the common .coop domain.
#
# It uses a minimal column schema including just organisation ID and
# domain fields. But the ID and domain fields for ICA is also included
# as the same schema will be shared by similar lists for the other
# data sets.
#
# (The org names are included purely for my own inspection
# convenience.)
#
# Note that in this case we need to join using an intermediate link
# table, dc_domains, because of the one-to-many relation from a DC
# organisation to the domains registered by it. This table is created
# to simplify later joins in queries, by linking DC and NCBA
# identifiers directly.
#
# The resulting table should have 1 row for each NCBA organisation in
# the ncba table that has a .coop domain, since the ncba dataset only
# allows one domain (via the website) to be associated.  NCBA
# organisations with no .coop domain are absent due to the way the
# join is done, but this is fine - we don't care about NCBA
# organisations with no .coop domain, since the purpose is to
# represent links where there are any.
#
# There should also be a 1:1 relation from NCBA organisations to DC
# organisations - so no duplicate dcid fields.  (In fact there is one
# case where one DC organisation maps to two NCBA organisations, which
# seems anomalous, see below. We work around that later, by assuming
# these are in fact distinct organsiations, and listing both.)
sqlite3 $DB "create view ncbaid_to_dcid as \
select \
  dc_domains.dcid as dcid, \
  dc.Name as dc_name, \
  dc.Domains as dc_domains, \
  ncba.Identifier as ncbaid, \
  ncba.Name as ncba_name, \
  ncba.Domain as ncba_domain, \
  NULL as icaid, \
  NULL as ica_name, \
  NULL as ica_domain \
from ncba \
left join dc_domains, dc on \
  ncba.Domain = dc_domains.domain and \
  dc_domains.dcid = dc.Identifier
";

# The problem case - in which two different ncba orgs link to same dc org:
#dcid	dc_name	dc_domains	ncbaid	ncba_name	ncba_domain	icaid	ica_name	ica_domain
#VKoYjW	NRTC	westflorida.coop;winntelwb.coop;victoriaelectric.coop;unitedwb.coop;vecbeatthepeak.coop;trueband.coop;ruralconnect.coop;shelbywb.coop;rswb.coop;oecc.coop;pemtel.coop;nrtc.coop;noblesce.coop;northriver.coop;nepower.coop;marshallremc.coop;mytimetv.coop;llwb.coop;localexede.coop;lcwb.coop;jasperremc.coop;infinium.coop;fcremc.coop;fultoncountyremc.coop;ctv.coop;cimarron.coop;cooperativewireless.coop;ccnc.coop;buynest.coop;bvea.coop;arcadiatel.coop	8227012210.0	National Rural Telecommunications Cooperative	nrtc.coop			
#VKoYjW	NRTC	westflorida.coop;winntelwb.coop;victoriaelectric.coop;unitedwb.coop;vecbeatthepeak.coop;trueband.coop;ruralconnect.coop;shelbywb.coop;rswb.coop;oecc.coop;pemtel.coop;nrtc.coop;noblesce.coop;northriver.coop;nepower.coop;marshallremc.coop;mytimetv.coop;llwb.coop;localexede.coop;lcwb.coop;jasperremc.coop;infinium.coop;fcremc.coop;fultoncountyremc.coop;ctv.coop;cimarron.coop;cooperativewireless.coop;ccnc.coop;buynest.coop;bvea.coop;arcadiatel.coop	8227153053.0	Cooperative Council of North Carolina	ccnc.coop			


# Ditto for ICA
#
# i.e Define a view which links those ICA organisations which have a
# .coop website to a DC organisation, via the common .coop domain.
#
# Again, using a minimal column schema including just organisation ID
# and domain fields, with blanks for NCBA, because the the same schema
# will be shared by similar lists for the other data sets.
#
# (The org names are included purely for my own inspection
# convenience.)
#
# Note that in this case we need to join using an intermediate link
# table, dc_domains, because of the one-to-many relation from a DC
# organisation to the domains registered by it. This table is created
# to simplify later joins in queries, by linking DC and NCBA
# identifiers directly.
#
# The resulting table should have 1 row for each ICA organisation in
# the ncba table that has a .coop domain, since the ncba dataset only
# allows one domain (via the website) to be associated.  ICA
# organisations with no .coop domain are absent due to the way the
# join is done, but this is fine - we don't care about them since the
# purpose is to represent links where there are any.
#
# There should also be a 1:1 relation from ICA organisations to DC
# organisations - so no duplicate dcid fields. (This does seem to be the case.)
sqlite3 $DB "create view icaid_to_dcid as \
select \
  dc_domains.dcid as dcid, \
  dc.Name as dc_name, \
  dc.Domains as dc_domains, \
  NULL as ncbaid, \
  NULL as ncba_name, \
  NULL as ncba_domain, \
  ica.Identifier as icaid, \
  ica.Name as ica_name, \
  ica.Domain as ica_domain \
from ica \
left join dc_domains, dc on \
  ica.Domain = dc_domains.domain and \
  dc_domains.dcid = dc.Identifier \
";


# Define a view listing all NCBA organisations with no link to a DC organisation.
#
# We use a minimal column schema including just organisation ID and
# domain fields, with blanks for non-NCBA fields, because the the same
# schema will be shared by similar lists for the other data sets.
#
# (The org names are included purely for my own inspection
# convenience.)
#
# The link is made using the ncbaid_to_dcid table.
#
# Some may be absent but there should be no more than one row for each
# NCBA organisation.
#
# There should also be no more than one of each DC organisation - so no
# duplicate dcid fields.  (In fact there is one case where one DC
# organisation maps to two NCBA organisations, which seems anomalous,
# see below. We work around that later...)
sqlite3 $DB "create view ncba_not_dc_orgs as \
select \
  NULL as dcid, \
  NULL as dc_name, \
  NULL as dc_domain, \
  ncba.Identifier as ncbaid, \
  ncba.Name as ncba_name, \
  ncba.Domain as ncba_domain, \
  NULL as icaid, \
  NULL as ica_name, \
  NULL as ica_domain \
from ncba \
left join ncbaid_to_dcid as n2d on \
  ncba.Identifier = n2d.ncbaid \
where \
  n2d.ncbaid is NULL \
"

# Ditto for ICA
#
# i.e. Define a view listing all ICA organisations with no link to a DC organisation.
#
# Note in principle, we should also exclude those with a link to NCBA
# organisations here. However, we have no way of doing that except via
# the .coop domain, so we don't.
#
# We use a minimal column schema including just organisation ID and
# domain fields, with blanks for non-NCBA fields, because the the same
# schema will be shared by similar lists for the other data sets.
#
# (The org names are included purely for my own inspection
# convenience.)
#
# The link is made using the icaid_to_dcid table.
#
# Some may be absent but there should be no more than one row for each
# ICA organisation.
#
# There should also be no more than one of each DC organisation - so no
# duplicate dcid fields.  (This seems to be the case.)
sqlite3 $DB "create view ica_not_dc_orgs as \
select \
  NULL as dcid, \
  NULL as dc_name, \
  NULL as dc_domain, \
  NULL as ncbaid, \
  NULL as ncba_name, \
  NULL as ncba_domain, \
  ica.Identifier as icaid, \
  ica.Name as ica_name, \
  ica.Domain as ica_domain \
from ica \
left join icaid_to_dcid as i2d on \
  ica.Identifier = i2d.icaid \
where \
  i2d.icaid is NULL \
"

# Define a view listing those DC orgs and their links to NCBA and/or ICA orgs
#
# There should be one row for each DC org, and that may include a link to an NCBA org,
# an ICA, both, or neither.
#
# (FIXME In fact we have more rows than DC orgs, because of the 1:2 match
# in one case to two NCBA organisations)
sqlite3 $DB "create view dc_orgs as \
select \
  dc.Identifier as dcid, \
  dc.Name as dc_name, \
  dc.Domains as dc_domains, \
  n2d.ncbaid as ncbaid, \
  n2d.ncba_name as ncba_name, \
  n2d.ncba_domain as ncba_domain, \
  i2d.icaid as icaid, \
  i2d.ica_name as ica_name, \
  i2d.ica_domain as ica_domain \
from dc \
left join ncbaid_to_dcid as n2d on \
  dc.Identifier = n2d.dcid \
left join icaid_to_dcid as i2d on \
  dc.Identifier = i2d.dcid \
;"

# Define a view which concatenates the above tables - this is why they have a common schema.
#
# Specifically:
# - DC registered organisations
# - non-DC registered NCBA organisations
# - non-DC registered (assumed non-NCBA) ICA orgs
#
# This is the unifying link table. However, note it does not have a
# unique ID for each row - but the ids together can provide the unique
# key.
#
sqlite3 $DB "create view all_orgs as \
select * from dc_orgs
union
select * from ncba_not_dc_orgs
union
select * from ica_not_dc_orgs
;"

# Create the final view for exporting the data for the map.
#
# As part of this, a globally unique ID field is generated.
#
# NOTE: we deliberately select the Identifier preferentially from ica,
# ncba, dc - rather than ica, dc, ncba as for the other fields.  This
# is because of a duplicate org match resulting in NCBA's orgs, ID
# 8227012210 and 8227153053, to match the same DotCoop org ID VKoYjW.
# A hacky workaround!
sqlite3 $DB <<'EOF'
create view map_data as
select 
  'demo/plus/'||coalesce(ica.slug,ncba.slug,dc.slug)||'/'||coalesce(ica.Identifier, ncba.Identifier, dc.Identifier) as Identifier,
  coalesce(ica.Name, dc.Name, ncba.Name) as Name,
  coalesce(ica.Description, dc.Description, ncba.Description) as Description,
  coalesce(ica.Website, dc.Website, ncba.Website) as Website,
  coalesce(ica.Latitude, dc.Latitude, ncba.Latitude) as Latitude,
  coalesce(ica.Longitude, dc.Longitude, ncba.Longitude) as Longitude,
  coalesce(ica.`Geo Container Latitude`, dc.`Geo Container Latitude`, ncba.`Geo Container Latitude`) as `Geo Container Latitude`,
  coalesce(ica.`Geo Container Longitude`, dc.`Geo Container Longitude`, ncba.`Geo Container Longitude`) as `Geo Container Longitude`,
  coalesce(ica.`Geo Container`, dc.`Geo Container`, ncba.`Geo Container`) as `Geo Container`,

  ncba.Identifier as `NCBA Identifier`,
  ncba.Postcode as `NCBA Postcode`,
  ncba.City as `NCBA City`,
  ncba.`State/Region` as `NCBA State/Region`,
  ncba.`Country ID` as `NCBA Country ID`,
  ncba.`Co-op Sector` as `NCBA Co-op Sector`,
  ncba.Industry as `NCBA Industry`,
  ncba.`Identifier` is not null as `NCBA Member`,

  ica.`Identifier` as `ICA Identifier`, 
  ica.`Name` as `ICA Name`,
  ica.`Street Address` as `ICA Street Address`,
  ica.`Locality` as `ICA Locality`,
  ica.`Region` as `ICA Region`,
  ica.`Postcode` as `ICA Postcode`,
  ica.`Country ID` as `ICA Country ID`,
  ica.`Website` as `ICA Website`,
  ica.`Primary Activity` as `ICA Primary Activity`,
  ica.`Activities` as `ICA Activities`,
  ica.`Organisational Structure` as `ICA Organisational Structure`,
  ica.`Membership Type` as `ICA Typology`,
  ica.`Identifier` is not null as `ICA Member`,
  
  dc.`Identifier` as `DC Identifier`, 
  dc.`Name` as `DC Name`,
  dc.`Street Address` as `DC Street Address`,
  dc.`Locality` as `DC Locality`,
  dc.`Region` as `DC Region`,
  dc.`Postcode` as `DC Postcode`,
  dc.`Country ID` as `DC Country ID`,
  dc.Domains as Domains,
  dc.`Economic Sector ID` as `DC Economic Sector`,
  dc.`Organisational Category ID` as `DC Organisational Category`,
  dc.`Identifier` is not null as `DC Registered`
from all_orgs
left join dc on all_orgs.dcid = dc.Identifier
left join ncba on all_orgs.ncbaid = ncba.Identifier
left join ica on all_orgs.icaid = ica.Identifier
EOF
