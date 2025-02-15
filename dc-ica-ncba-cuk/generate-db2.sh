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
# A unified CSV, usable by a Mykomap, is written out as a last step.
#
#
# USAGE
# 
# Define the following environment variables, then run the
# `generate-db2.sh` script with no options.
#
# An intermediate Sqlite3 database will be constructed.  This will
# contain a table `map_data` which defines what will be used by the
# consuming Mykomap.
#
# defs.sh should define the following environment variables:
#
# - DC_CSV: the name of a 'standard Mykomap schema' CSV file containing the DotCoop organisation data 
# - DC_TB: the name of a database table to import that to
# - DC_FK: the name of the primary key field of that table.
# - ICA_CSV, ICA_TB, ICA_FK: ditto, but for the ICA data
# - NCBA_CSV, NCBA_TB, NCBA_FK: ditto, but for the NCBA data
# - CUK_CSV, CUK_TB, CUK_FK: ditto, but for the CUK data
# - DB: the filename of the Sqlite3 database to create
# - OUT_CSV: the name of a CSV to dump the `map_data` table to
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
# Note: sometimes the DC table is inconsistent with the NCBA, ICA and
# CUK domains! So you may find .coop domains in the latter which
# aren't in the former.
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
#     all_orgs = dc + (ncba - dc) + (ica - dc - ncba) + (cuk - dc - ncba - ica)
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
# 4) Add CUK organisations without .coop domain or NCBA or ICA links
#    [ left join `dc_domains` to `cuk` on the domain, select those with no .coop domain ]
#    [ we cannot identify overlaps between CUK, ICA and NCBA currently ]
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

set -e

expected=(
    DC_CSV DC_TB DC_FK ICA_CSV ICA_TB ICA_FK NCBA_CSV NCBA_TB NCBA_FK
    CUK_CSV CUK_TB CUK_FK DB OUT_CSV
)
for name in ${expected[@]}; do
    echo "$name=${!name:?mandatory $name environment variable is not set}"
done

{ # Parse and validate the command options
    while getopts "y" option; do
        case $option in 
            y) OVERWRITE_DB=1;; # force DB overwrite
	    *) 
		echo "Invalid option: $OPTARG"
		exit 1
		;;
	esac
    done
    shift $(( $OPTIND - 1 ))
}

# Safety first - don't blindly overwrite database if it exists
if [ -e $DB ]; then
    if [ -z "$OVERWRITE_DB" ]; then
	read -p "Overwrite $DB? [Y/N]" response
	if [[ "$response" != "Y" ]]; then
	    echo "Stopping."
	    exit 1;
	fi
    fi
    rm -f $DB;
fi

set -vx

# --blanks is important otherwise 'NA', 'N/A', 'none' or 'null' -> null!
csvsql --db sqlite:///$DB --tables $DC_TB --blanks --no-constraints --insert $DC_CSV
csvsql --db sqlite:///$DB --tables $ICA_TB --blanks --no-constraints --insert $ICA_CSV
csvsql --db sqlite:///$DB --tables $NCBA_TB --blanks --no-constraints --insert $NCBA_CSV
csvsql --db sqlite:///$DB --tables $CUK_TB --blanks --no-constraints --insert $CUK_CSV

function sql() {
    sqlite3 "$DB" "$@"
}

# Halts with an error if the standard input to this function is not empty.
# Used for making assertions about SQL statements.
function if_not_empty() {
    local out=$(cat)
    if [[ $out != '' ]]; then
	echo "Assertion failed, $*" 2>&1
	echo "$out" 2>&1
	exit 1;
    fi 
}


# Add Domains field to $DC_TB
sql "alter table $DC_TB add column Domains VARCHAR"

# For ICA, CUK: Copy Website URLs as Domain
for TB in $ICA_TB $CUK_TB; do
    # Add Domain field
    sql "alter table $TB add column Domain VARCHAR"
    sql "update $TB set Domain = Website"
done

# For ICA, NCBA - make the Identifier field an integer (not a real)
# Otherwise, sqlite will insert a trailing '.0' on export
for TB in $ICA_TB $NCBA_TB $CUK_TB; do
    sql "alter table $TB add column temp INTEGER"
    sql "update $TB set temp = Identifier"
    sql "alter table $TB drop column Identifier"
    sql "alter table $TB rename column temp to Identifier"
done

# For ICA, NCBA, CUK: clean them up into bare domains
for TB in $ICA_TB $NCBA_TB $CUK_TB; do
    # Make add a unique index on Identifier
    sql "alter table $TB add column temp VARCHAR NOT NULL DEFAULT '-'"
    sql "update $TB set temp = Identifier"
    sql "alter table $TB drop column Identifier"
    sql "alter table $TB rename column temp to Identifier"
    sql "create unique index ${TB}Identifier on $TB (Identifier)"
    
    sql "update $TB set Domain = lower(Domain)"
    sql "update $TB set Domain = replace(Domain, 'http://', '')"
    sql "update $TB set Domain = replace(Domain, 'https://', '')"
    sql "update $TB set Domain = replace(Domain, 'http://', '')"
    sql "update $TB set Domain = substr(Domain, 0, instr(Domain||'/','/'));" # remove paths
    sql "update $TB set Domain = substr(Domain, instr(Domain, '.')+1) where Domain like '%.%.coop'"; # remove subdomains - well, one level.
    sql "update $TB set Domain = substr(Domain, instr(Domain, '.')+1) where Domain like '%.%.coop'"; # second
    sql "update $TB set Domain = substr(Domain, instr(Domain, '.')+1) where Domain like '%.%.coop'"; # third?
    # Remove any remaining www. subdomains
    sql "update $TB set Domain = substr(Domain, instr(Domain, '.')+1) where Domain like 'www.%.%'"; # third?
done

# Cleanup for all datasets
for TB in $ICA_TB $NCBA_TB $DC_TB $CUK_TB; do
    # Replace empty strings which represent nulls with nulls
    sql "select f.name from sqlite_master t, pragma_table_info((t.name)) f on t.name <> f.name where t.name = '$TB'" |
	while IFS=$'\n' read -rs FIELD; do
	    sql "update $TB set \`$FIELD\` = NULL where \`$FIELD\` = '';"
	done
		   
    # Any orgs with lat/lng 0,0 should be set to null (this is a problem with ICA data at least,
    # which may need fixing properly upstream
    sql "update $TB set Latitude = null, Longitude = null where Latitude = 0 and Longitude = 0;"

    # insert a slug field identifying the dataset
    sql "alter table $TB add column slug VARCHAR"
    sql "update $TB set slug = '$TB'"    
done

# Likewise for DC, copy Website into Domains and clean up (although less cleaning needed)
sql "update $DC_TB set Domains = lower(Website)"
sql "update $DC_TB set Domains = replace(Domains, 'http://', '')"
sql "update $DC_TB set Domains = replace(Domains, 'https://', '')"

# Convert adhoc to vocab fields...?

# Compile a table of DC domains to DC identifiers.
# We have to go beyond SQL into Perl here, SQL can't easily to the splitting and joining.
# Insert the result back immediately as a new 1:* table
sql -csv "select Identifier, Domains from $DC_TB" |
    (
	printf "domain,${DC_FK}\n"
	perl -nE 'chomp; ($id,$d) = split /,/; @d = split /;/, $d; say "$_,$id" for @d'
    ) | csvsql --db sqlite:///$DB --tables domains --insert --no-constraints -

# Add $ICA_FK and $NCBA_FK fields, and indexes on them
for FK in $ICA_FK $NCBA_FK $CUK_FK; do 
    sql "alter table domains add column $FK VARCHAR"
    sql "create unique index $FK on domains ($FK)"
done

# ...and the domains field ($DC_FK there already)
sql "create index domain on domains (domain)"
sql "create index $DC_FK on domains ($DC_FK)"

######################################################################
# At this point we have sanitised the input data and normalised and
# separated out the linking domains.
#
# Next we can start combining them. We need to create a unifying grand
# list of organisations, with foreign key links back to the original
# organisation tables.

# Before we add more domains from other datasets, create a table
# linking all the .coop domains to their DC registrant orgs.
sql "create table dc_domains as select domain, dcid from domains;"


# Create foreign refs from domains to $NCBA_TB, $ICA_TB and $CUK_TB
# tables based on Domains/Domain matches
sql "insert into domains (domain,$ICA_FK) select $ICA_TB.Domain,$ICA_TB.Identifier from $ICA_TB;"
sql "insert into domains (domain,$NCBA_FK) select $NCBA_TB.Domain,$NCBA_TB.Identifier from $NCBA_TB;"
sql "insert into domains (domain,$CUK_FK) select $CUK_TB.Domain,$CUK_TB.Identifier from $CUK_TB;"

# Create a frequency table listing unique domains found and the number
# of times they appear in DC, ICA and NCBA databases. This is not used
# directly later, but is useful for analysing the data - notably
# knowing when assumptions about domains are not valid!
sql <<EOF
create table domain_freq as
select
  domain,
  count(dcid) as dc,
  count(icaid) as ica,
  count(ncbaid) as ncba,
  count(cukid) as cuk
from domains
group by domain
EOF

# Assert our assumptions about NCBA orgs having only one matching DC org are true
# Except we happen to know this is true, but work around it, counting this as two orgs
# sql <<EOF | if_not_empty "Duplicate NCBA identifier"
# select
#   count(ncba.Identifier) as c,
#   ncba.Identifier as ncbaid,
#   dc.Identifier as dcid
# from ncba
# left join dc_domains, dc on
#   ncba.Domain = dc_domains.domain and
#   dc_domains.dcid = dc.Identifier
# group by dc.Identifier
# having c > 1;
# EOF

# Assert our assumptions about ICA orgs having only one matching DC org are true
sql <<EOF | if_not_empty "Duplicate ICA identifier"
select
  count(ica.Identifier) as c,
  ica.Identifier as icaid,
  dc.Identifier as dcid
from ica
left join dc_domains, dc on
  ncba.Domain = dc_domains.domain and
  dc_domains.dcid = dc.Identifier
group by dc.Identifier
having c > 1;
EOF

# # Assert our assumptions about CUK orgs having only one matching DC org are true
# Except we happen to know this is true, but work around it, by excluding the
# duplicates later.
# sql <<EOF | if_not_empty "Duplicate CUK identifier"
# select
#   count(cuk.Identifier) as c,
#   cuk.Identifier as cukid,
#   dc.Identifier as dcid
# from cuk
# left join dc_domains, dc on
#   cuk.Domain = dc_domains.domain and
#   dc_domains.dcid = dc.Identifier
# group by dc.Identifier
# having c > 1;
# EOF


# Define a view which links those NCBA organisations which have a .coop
# website to a DC organisation, via the common .coop domain.
#
# It uses a minimal column schema including just organisation ID and
# domain fields.
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
sql <<EOF
create view ncbaid_to_dcid as
select
  dc_domains.dcid as dcid,
  dc.Name as dc_name,
  dc.Domains as dc_domains,
  ncba.Identifier as ncbaid,
  ncba.Name as ncba_name,
  ncba.Domain as ncba_domain
from ncba
left join dc_domains, dc on
  ncba.Domain = dc_domains.domain and
  dc_domains.dcid = dc.Identifier
EOF

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
# and domain fields.
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
sql <<EOF
create view icaid_to_dcid as
select
  dc_domains.dcid as dcid,
  dc.Name as dc_name,
  dc.Domains as dc_domains,
  ica.Identifier as icaid,
  ica.Name as ica_name,
  ica.Domain as ica_domain
from ica
left join dc_domains, dc on
  ica.Domain = dc_domains.domain and
  dc_domains.dcid = dc.Identifier
EOF


# Ditto for CUK
#
# i.e Define a view which links those CUK organisations which have a
# .coop website to a DC organisation, via the common .coop domain.
#
# All the above comments apply.
#
# Except that the CUK data has a lot of .coop links which are
# duplicates.  We can't easily identify which, if any, of these CUK
# organisations really match the DC organisation which registered the
# .coop domain. In fact, it looks like possibly none do in several
# cases. Maybe an apex .coop registrant is allowing its members to use
# its domain as their primary website? (Housing co-ops in particular
# seem to be doing this.)
#
# To work around this, we simply eliminate any CUK organisations which
# share a DC domain and leave them as distinct organisations, even if
# perhaps they are the same one. 
sql <<EOF
create view cukid_to_dcid as
select
  dc_domains.dcid as dcid,
  dc.Name as dc_name,
  dc.Domains as dc_domains,
  cuk.Identifier as cukid,
  cuk.Name as cuk_name,
  cuk.Domain as cuk_domain
from cuk
left join dc_domains, dc on
  cuk.Domain = dc_domains.domain and
  dc_domains.dcid = dc.Identifier
group by dcid
having count(dcid) <= 1;
EOF


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
sql <<EOF
create view ncba_not_dc_orgs as
select
  NULL as dcid,
  NULL as dc_name,
  NULL as dc_domain,
  ncba.Identifier as ncbaid,
  ncba.Name as ncba_name,
  ncba.Domain as ncba_domain,
  NULL as icaid,
  NULL as ica_name,
  NULL as ica_domain,
  NULL as cukid,
  NULL as cuk_name,
  NULL as cuk_domain
from ncba
left join ncbaid_to_dcid as n2d on
  ncba.Identifier = n2d.ncbaid
where
  n2d.ncbaid is NULL
EOF

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
# duplicate dcid fields.  (This seems to be the case...)
sql <<EOF
create view ica_not_dc_orgs as
select
  NULL as dcid,
  NULL as dc_name,
  NULL as dc_domain,
  NULL as ncbaid,
  NULL as ncba_name,
  NULL as ncba_domain,
  ica.Identifier as icaid,
  ica.Name as ica_name,
  ica.Domain as ica_domain,
  NULL as cukid,
  NULL as cuk_name,
  NULL as cuk_domain
from ica
left join icaid_to_dcid as i2d on
  ica.Identifier = i2d.icaid
where
  i2d.icaid is NULL
EOF

# Ditto for CUK
#
# i.e. Define a view listing all CUK organisations with no link to a DC organisation.
#
# Note in principle, we should also exclude those with a link to NCBA
# and ICA organisations here. However, we have no way of doing that
# except via the .coop domain, so we don't.
#
# We use a minimal column schema including just organisation ID and
# domain fields, with blanks for non-NCBA fields, because the the same
# schema will be shared by similar lists for the other data sets.
#
# (The org names are included purely for my own inspection
# convenience.)
#
# The link is made using the cukid_to_dcid table.
#
# Some may be absent but there should be no more than one row for each
# CUK organisation.
#
# There should also be no more than one of each DC organisation - so
# no duplicate dcid fields. (We make sure of this by excluding
# duplicates from the cukid_to_dcid table)
sql <<EOF
create view cuk_not_dc_orgs as
select
  NULL as dcid,
  NULL as dc_name,
  NULL as dc_domain,
  NULL as ncbaid,
  NULL as ncba_name,
  NULL as ncba_domain,
  NULL as icaid,
  NULL as ica_name,
  NULL as ica_domain,
  cuk.Identifier as cukid,
  cuk.Name as cuk_name,
  cuk.Domain as cuk_domain
from cuk
left join cukid_to_dcid as c2d on
  cuk.Identifier = c2d.cukid
where
  c2d.cukid is NULL
EOF

# Define a view listing those DC orgs and their links to NCBA and/or ICA and/or CUK orgs
#
# There should be one row for each DC org, and that may include a link to an NCBA org,
# an ICA, or a CUK org, or some combination thereof.
#
# (FIXME In fact we have more rows than DC orgs, because of the 1:2 match
# in one case to two NCBA organisations)
sql <<EOF
create view dc_orgs as
select
  dc.Identifier as dcid,
  dc.Name as dc_name,
  dc.Domains as dc_domains,
  n2d.ncbaid as ncbaid,
  n2d.ncba_name as ncba_name,
  n2d.ncba_domain as ncba_domain,
  i2d.icaid as icaid,
  i2d.ica_name as ica_name,
  i2d.ica_domain as ica_domain,
  c2d.cukid as cukid,
  c2d.cuk_name as cuk_name,
  c2d.cuk_domain as cuk_domain
from dc
left join ncbaid_to_dcid as n2d on
  dc.Identifier = n2d.dcid
left join icaid_to_dcid as i2d on
  dc.Identifier = i2d.dcid
left join cukid_to_dcid as c2d on
  dc.Identifier = c2d.dcid
EOF

# Define a view which concatenates the above tables - this is why they have a common schema.
#
# Specifically:
# - DC registered organisations
# - non-DC registered NCBA organisations
# - non-DC registered (assumed non-NCBA) ICA orgs
# - non-DC registered (assumed non-NCBA non-ICA) CUK orgs
#
# This is the unifying link table. However, note it does not have a
# unique ID for each row - but the ids together can provide the unique
# key.
#
sql <<EOF
create view all_orgs as
  select * from dc_orgs
union
  select * from ncba_not_dc_orgs
union
  select * from ica_not_dc_orgs
union
  select * from cuk_not_dc_orgs
EOF

# Create the final view for exporting the data for the map.
#
# As part of this, a globally unique ID field is generated.
#
# NOTE: we deliberately select the Identifier preferentially from ica,
# ncba, dc, cuk - rather than ica, dc, ncba, cuk as for the other fields.  This
# is because of a duplicate org match resulting in NCBA's orgs, ID
# 8227012210 and 8227153053, to match the same DotCoop org ID VKoYjW.
# A hacky workaround!
#
# Note we are also assuming that if one latitude or longitude value is
# present, the other will be.  This should be valid. If it were not
# however, we'd get mixed and matched coordinates, i.e.
# nonesense coordinates.
#
# See this point for how we coalesce the various `Country ID` fields into one
# https://github.com/DigitalCommons/mykomap/issues/249#issuecomment-2150534302
sql <<'EOF'
create view map_data as
select 
  'demo/plus/'||coalesce(ica.slug,ncba.slug,dc.slug,cuk.slug)||'/'||coalesce(ica.Identifier, ncba.Identifier, dc.Identifier, cuk.Identifier) as Identifier,
  coalesce(ica.Name, dc.Name, ncba.Name, cuk.Name) as Name,
  coalesce(ica.Description, dc.Description, ncba.Description, cuk.Description) as Description,
  coalesce(ica.Website, ncba.Website, cuk.Website) as Website,
  coalesce(cuk.`Country ID`, ica.`Country ID`, dc.`Country ID`, ncba.`Country ID`) as `Country ID`,
  coalesce(ica.`Primary Activity`, cuk.`Primary Activity`, dc.`Primary Activity`) as `Primary Activity`,
  coalesce(ica.`Organisational Structure`, cuk.`Organisational Structure`, dc.`Organisational Structure`) as `Organisational Structure`,
  coalesce(ica.`Membership Type`, cuk.`Membership Type`, dc.`Membership Type`) as `Typology`,
  coalesce(ica.Latitude, cuk.Latitude, dc.Latitude, ncba.Latitude) as Latitude,
  coalesce(ica.Longitude, cuk.Longitude, dc.Longitude, ncba.Longitude) as Longitude,
  coalesce(ica.`Geo Container Latitude`, cuk.`Geo Container Latitude`, dc.`Geo Container Latitude`, ncba.`Geo Container Latitude`) as `Geo Container Latitude`,
  coalesce(ica.`Geo Container Longitude`, cuk.`Geo Container Longitude`, dc.`Geo Container Longitude`, ncba.`Geo Container Longitude`) as `Geo Container Longitude`,
  coalesce(ica.`Geo Container`, cuk.`Geo Container`, dc.`Geo Container`, ncba.`Geo Container`) as `Geo Container`,
  coalesce(ica.`Geocoded Address`, cuk.`Geocoded Address`, dc.`Geocoded Address`, ncba.`Geocoded Address`) as `Geocoded Address`,

  ncba.Identifier as `NCBA Identifier`,
  ncba.Name as `NCBA Name`,
  ncba.Postcode as `NCBA Postcode`,
  ncba.City as `NCBA City`,
  ncba.`State/Region` as `NCBA State/Region`,
  ncba.`Country ID` as `NCBA Country ID`,
  ncba.Domain as `NCBA Domain`,
  ncba.`Primary Activity` as `NCBA Primary Activity`,
  ncba.`Co-op Sector` as `NCBA Co-op Sector`,
  ncba.Industry as `NCBA Industry`,
  ncba.`Geocoded Address` as `NCBA Geocoded Address`,
  ncba.`Geo Container Confidence` as `NCBA Geo Container Confidence`,
  ncba.`Identifier` is not null as `NCBA Member`,

  ica.`Identifier` as `ICA Identifier`, 
  ica.`Name` as `ICA Name`,
  ica.`Street Address` as `ICA Street Address`,
  ica.`Locality` as `ICA Locality`,
  ica.`Region` as `ICA Region`,
  ica.`Postcode` as `ICA Postcode`,
  ica.`Country ID` as `ICA Country ID`,
  ica.`Territory ID` as `ICA Territory ID`,
  ica.`Website` as `ICA Website`,
  ica.`Primary Activity` as `ICA Primary Activity`,
  ica.`Activities` as `ICA Activities`,
  ica.`Organisational Structure` as `ICA Organisational Structure`,
  ica.`Membership Type` as `ICA Typology`,
  ica.`Geocoded Address` as `ICA Geocoded Address`,
  ica.`Geo Container Confidence` as `ICA Geo Container Confidence`,
  ica.`Identifier` is not null as `ICA Member`,
  
  dc.`Identifier` as `DC Identifier`, 
  dc.`Name` as `DC Name`,
  dc.`Street Address` as `DC Street Address`,
  dc.`Locality` as `DC Locality`,
  dc.`Region` as `DC Region`,
  dc.`Postcode` as `DC Postcode`,
  dc.`Country ID` as `DC Country ID`,
  dc.`Domains` as `DC Domains`,
  dc.`Primary Activity` as `DC Primary Activity`,
  dc.`Organisational Structure` as `DC Organisational Structure`,
  dc.`Membership Type` as `DC Typology`,
  dc.`Economic Sector ID` as `DC Economic Sector`,
  dc.`Organisational Category ID` as `DC Organisational Category`,
  dc.`Geocoded Address` as `DC Geocoded Address`,
  dc.`Geo Container Confidence` as `DC Geo Container Confidence`,
  dc.`Identifier` is not null as `DC Registered`,

  cuk.`Identifier` as `CUK Identifier`, 
  cuk.`Name` as `CUK Name`,
  cuk.`Street Address` as `CUK Street Address`,
  cuk.`Locality` as `CUK Locality`,
  cuk.`Region` as `CUK Region`,
  cuk.`Postcode` as `CUK Postcode`,
  cuk.`Country ID` as `CUK Country ID`,
  cuk.`Website` as `CUK Website`,
  cuk.`Primary Activity` as `CUK Primary Activity`,
  cuk.`Activities` as `CUK Activities`,
  cuk.`Organisational Structure` as `CUK Organisational Structure`,
  cuk.`Membership Type` as `CUK Typology`,
  cuk.`Companies House Number` as `CUK Companies House Number`,
  cuk.`Sector` as `CUK Sector`,
  cuk.`SIC Section` as `CUK SIC Section`,
  cuk.`SIC Code` as `CUK SIC Code`,
  cuk.`Ownership Classification` as `CUK Ownership Classification`,
  cuk.`Legal Form` as `CUK Legal Form`,
  cuk.`Geocoded Address` as `CUK Geocoded Address`,
  cuk.`Geo Container Confidence` as `CUK Geo Container Confidence`,
  cuk.`Identifier` is not null as `CUK Member`
from all_orgs
left join dc on all_orgs.dcid = dc.Identifier
left join ncba on all_orgs.ncbaid = ncba.Identifier
left join ica on all_orgs.icaid = ica.Identifier
left join cuk on all_orgs.cukid = cuk.Identifier
EOF


# Find cases where the non-null country IDs of organisations differ.
#
# First get a table mapping organisation IDs to their country ID, from
# all datasets.  i.e. select id, cid for all cases where cid is not
# null
#
# Then group by ID and count those with more than one entry (because
# the ID has been listed against more than one Country)
#
# Here we include the Name field as a convenience
sql <<'EOF'
create view uncorrelated_country_ids as
select distinct count(cid) as c, group_concat(cid) as cids, id, n as name,
  `DC Country ID`, `ICA Country ID`, `NCBA Country ID`, `CUK Country ID`,
  `DC Domains`, `ICA Website`, `NCBA Domain`, `CUK Website`,
  `DC Name`, 
  `ICA Name`, `ICA Street Address`, `ICA Locality`, `ICA Territory ID`,
  `NCBA name`,
  `CUK Name`, `CUK Street Address`, `CUK Locality`
  
from (
  select `DC Country ID` as cid, Identifier as id, Name as n  from map_data where cid is not null
  union
  select `ICA Country ID` as cid, Identifier as id, Name as n  from map_data where cid is not null
  union
  select `NCBA Country ID` as cid, Identifier as id, Name as n  from map_data where cid is not null
  union
  select `CUK Country ID` as cid, Identifier as id, Name as n  from map_data where cid is not null
) 
left join map_data on id = map_data.Identifier
group by id having c > 1
EOF

# Similar query as above, but for uncorrelated organisational names
sql <<'EOF'
CREATE VIEW uncorrelated_names as
select distinct count(n) as c, group_concat(n) as names,
  `DC Country ID`, `ICA Country ID`, `NCBA Country ID`, `CUK Country ID`,
  `DC Domains`, `ICA Website`, `NCBA Domain`, `CUK Website`,
  `DC Name`, 
  `ICA Name`, `ICA Street Address`, `ICA Locality`, `ICA Territory ID`,
  `NCBA name`,
  `CUK Name`, `CUK Street Address`, `CUK Locality`
  
from (
  select `DC Name` as n, Identifier as id  from map_data where n is not null
  union
  select `ICA Name` as n, Identifier as id  from map_data where n is not null
  union
  select `NCBA Name` as n, Identifier as id  from map_data where n is not null
  union
  select `CUK Name` as n, Identifier as id  from map_data where n is not null
) 
left join map_data on id = map_data.Identifier
group by id having c > 1
EOF

# This tries to find duplicate names shared by what are listed as separate organisations in the data
sql <<'EOF'
CREATE VIEW duplicate_names as
select Name, count(Identifier) as count, group_concat(Identifier) as ids from map_data
group by Name
having count > 1
order by count desc;
EOF

# This tries to find mismatching Primary Activity values
sql <<'EOF'
CREATE VIEW uncorrelated_primary_activities as
select distinct count(pa) as c, group_concat(replace(pa,'https://dev.lod.coop/essglobal/2.1/standard/activities-ica/','')) as pas, id, n as name,
  `DC Primary Activity`, `ICA Primary Activity`, `CUK Primary Activity`,
  `DC Domains`, `ICA Website`, `NCBA Domain`, `CUK Website`,
  `DC Name`, 
  `ICA Name`, `ICA Street Address`, `ICA Locality`, `ICA Territory ID`,
  `NCBA name`,
  `CUK Name`, `CUK Street Address`, `CUK Locality`
  
from (
  select `DC Primary Activity` as pa, Identifier as id, Name as n  from map_data where pa is not null
  union
  select `ICA Primary Activity` as pa, Identifier as id, Name as n  from map_data where pa is not null
  union
  select `CUK Primary Activity` as pa, Identifier as id, Name as n  from map_data where pa is not null
) 
left join map_data on id = map_data.Identifier
group by id having c > 1
EOF

# This tries to find mismatching Organisational Structure values
sql <<'EOF'
CREATE VIEW uncorrelated_organisational_structures as
select distinct count(os) as c, group_concat(replace(os,'https://dev.lod.coop/essglobal/2.1/standard/organisational-structure/','')) as oss, id, n as name,
  `DC Organisational Structure`, `ICA Organisational Structure`, `CUK Organisational Structure`,
  `DC Domains`, `ICA Website`, `NCBA Domain`, `CUK Website`,
  `DC Name`,
  `ICA Name`, `ICA Street Address`, `ICA Locality`, `ICA Territory ID`,
  `NCBA name`,
  `CUK Name`, `CUK Street Address`, `CUK Locality`
  
from (
  select `DC Organisational Structure` as os, Identifier as id, Name as n  from map_data where os is not null
  union
  select `ICA Organisational Structure` as os, Identifier as id, Name as n  from map_data where os is not null
  union
  select `CUK Organisational Structure` as os, Identifier as id, Name as n  from map_data where os is not null
) 
left join map_data on id = map_data.Identifier
group by id having c > 1
EOF

# This tries to find mismatching Typology values
sql <<'EOF'
CREATE VIEW uncorrelated_typologies as
select distinct count(ty) as c, group_concat(replace(ty,'https://dev.lod.coop/essglobal/2.1/standard/base-membership-type/','')) as tys, id, n as name,
  `DC Typology`, `ICA Typology`, `CUK Typology`,
  `DC Domains`, `ICA Website`, `NCBA Domain`, `CUK Website`,
  `DC Name`,
  `ICA Name`, `ICA Street Address`, `ICA Locality`, `ICA Territory ID`,
  `NCBA name`,
  `CUK Name`, `CUK Street Address`, `CUK Locality`
  
from (
  select `DC Typology` as ty, Identifier as id, Name as n  from map_data where ty is not null
  union
  select `ICA Typology` as ty, Identifier as id, Name as n  from map_data where ty is not null
  union
  select `CUK Typology` as ty, Identifier as id, Name as n  from map_data where ty is not null
) 
left join map_data on id = map_data.Identifier
group by id having c > 1
EOF

# A slimmed-down version which will hopefully load faster.
# We keep map_data as it's still used for diagnostics and investigation.
sql <<'EOF'
create view map_data_lite as
select 
  Identifier,
  Name,
  Description,
  Website,
  `DC Domains`,
  `Country ID`,
  replace(map_data.`Primary Activity`, 'https://dev.lod.coop/essglobal/2.1/standard/activities-ica/', '') as `Primary Activity`,
  replace(map_data.`Organisational Structure`, 'https://dev.lod.coop/essglobal/2.1/standard/organisational-structure/', '') as `Organisational Structure`,
  replace(map_data.`Typology`, 'https://dev.lod.coop/essglobal/2.1/standard/base-membership-type/', '') as `Typology`,
  Latitude,
  Longitude,
  `Geo Container Latitude`,
  `Geo Container Longitude`,
  `Geocoded Address`,
  `NCBA Member`,
  `ICA Member`,
  `DC Registered`,
  `CUK Member`,
  `CUK Sector`
from map_data
EOF


# Dump this map_data_lite view to OUT_CSV for use in a Mykomap.
sql -csv -header >"$OUT_CSV" "select * from map_data_lite"
