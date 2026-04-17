# Data Standard

Source CSVs are normalised into a standard format before being passed to the 
Mykomap dataset script. This document describes that standard and how to write 
a `converter.rb` script for a new project.

## Standard fields

The standard format is defined in 
`tools/se_open_data/lib/se_open_data/csv/standard.rb` and contains the following 
fields:

| Symbol | CSV Header |
|--------|------------|
| `id` | Identifier |
| `name` | Name |
| `description` | Description |
| `organisational_structure` | Organisational Structure |
| `primary_activity` | Primary Activity |
| `activities` | Activities |
| `street_address` | Street Address |
| `locality` | Locality |
| `region` | Region |
| `postcode` | Postcode |
| `country_name` | Country Name |
| `homepage` | Website |
| `phone` | Phone |
| `email` | Email |
| `twitter` | Twitter |
| `facebook` | Facebook |
| `companies_house_number` | Companies House Number |
| `latitude` | Latitude |
| `longitude` | Longitude |
| `geocontainer` | Geo Container |
| `geocontainer_lat` | Geo Container Latitude |
| `geocontainer_lon` | Geo Container Longitude |

## Writing a converter

Each project contains a `converter.rb` script that maps fields from the source CSV 
to the standard format. These are found in `data/[project_name]/[project_version]/`.

### Passing fields through directly

To pass a field straight through from source to output, add it to `InputHeaders`, 
mapping the standard symbol to the source CSV header name:

```ruby
InputHeaders = {
  id: "ID",
  name: "Name",
  description: "Description"
}
```

When the script runs, values from the `ID` column in the source will be placed in 
the `Identifier` column of the output, and so on.

### Processing fields before output

If you need to transform or combine fields before passing them to the output, define 
a method with the same name as the standard symbol. The return value will be used 
as the output. For example, to combine multiple address fields into one:

```ruby
InputHeaders = {
  id: "ID",
  name: "Name",
  description: "Description",
  address1: "Address1",
  address2: "Address2",
  address3: "Address3"
}

def street_address
  [
    !address1.empty? ? address1 : nil,
    !address2.empty? ? address2 : nil,
    !address3.empty? ? address3 : nil
  ].compact.join(OutputStandard::SubFieldSeparator)
end
```

## Running the conversion

From the project version directory:

```bash
make -f csv.mk edition=experimental
```

Output files are placed in `generated-data/[edition]/`:
- `standard.csv` — the normalised output
- `csv/initiatives.csv` — intermediate file
- `csv/report.csv` — any notes or warnings generated during conversion

### If you need to re-run

Remove the generated files first:

```bash
rm -rf generated-data/[edition]/csv
rm generated-data/[edition]/standard.csv
rm generated-data/[edition]/www/doc/*.*
```
