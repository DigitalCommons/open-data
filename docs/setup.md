# Setup

## Requirements

- Unix/Linux environment (macOS or Ubuntu recommended). Windows users should use WSL.
- Ruby and the following gems: `nokogiri`, `linkeddata`, `prawn`, `prawn-table`,
  `levenshtein`, `opencage-geocoder`
- GNU Make

## Installing development tools

### macOS

1. Open **Terminal** (located in `Applications/Utilities`)
2. Run `xcode-select --install` and click **Install** when prompted

You'll also need a package manager. We recommend [Homebrew](https://brew.sh/):

```bash
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

### Ubuntu

```bash
sudo apt-get update
sudo apt-get install build-essential patch ruby-dev zlib1g-dev liblzma-dev git
```

## Installing Ruby gems

The following commands are the same for macOS and Ubuntu:

```bash
sudo gem install nokogiri
sudo gem install linkeddata
sudo gem install prawn
sudo gem install prawn-table
sudo gem install levenshtein
sudo gem install opencage-geocoder
```

## Cloning the repository

```bash
git clone https://github.com/DigitalCommons/open-data.git
```

## Secure files

Before you can run the scripts you will need the following files, which should be 
requested from the repository manager:

- **Geoapify API key** — place at `open-data/APIs/geoapifyAPI.txt`
- **Source CSV data** — place in `original-data/` within the relevant project folder
- **Cache file** — place in the top-level directory of the relevant project folder

## SSH access (required for deployment only)

To deploy files to the web server you will need SSH access. Generate an SSH key pair:

### macOS

```bash
ssh-keygen -t rsa
```

### Ubuntu

```bash
ssh-keygen
```

Accept the default file location and choose a passphrase when prompted.

> ⚠️ Never share your private key with anyone.

Copy your public key to the clipboard:

**macOS:**
```bash
pbcopy < ~/.ssh/id_rsa.pub
```

**Ubuntu:**
```bash
cat ~/.ssh/id_rsa.pub
```

Then ask someone with existing server access to add it to `~/.ssh/authorized_keys` 
on the server for the `joe` and `admin` accounts.

On your local machine, add the following to `~/.ssh/config`:

```
Host sea-0-joe
  Hostname 51.15.116.30
  Port 22
  IdentityFile ~/.ssh/id_rsa
  HostbasedAuthentication yes
  PubkeyAuthentication yes
  PasswordAuthentication no
  User joe

Host sea-0-admin
  Hostname 51.15.116.30
  Port 22
  IdentityFile ~/.ssh/id_rsa
  HostbasedAuthentication yes
  PubkeyAuthentication yes
  PasswordAuthentication no
  User admin
```
