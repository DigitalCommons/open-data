# Domains always kept or always dropped when deriving Domains from Website.
# Copied from data-pipelines packages/dataset-build/src/annotations.ts.
module UnifiedCsv
  module DomainLists
    WHITELIST = Set.new(%w[
      greenstar.coop
      hendersonville.coop
      institute.coop
      lamontanita.coop
      outpost.coop
      pccmarkets.com
      radiateconsulting.coop
      weaversway.coop
      weaverstreetmarket.coop
      willystreet.coop
      zenchu-ja.or.jp
    ]).freeze

    BLACKLIST = Set.new(%w[
      afdr.coop
      arctic-coop.com
      blogspot.ca
      blogspot.co.uk
      blogspot.com
      btck.co.uk
      business.site
      cf2r.coop
      cfa.coop
      cfmm.coop
      cftemiscamingue.coop
      cimetiere.coop
      cimetieres.coop
      coopfuneraires.coop
      coophomes.coop
      country-markets.co.uk
      edinburghsolar.coop
      fjord.coop
      forestieresgaspesie.coop
      funeralnetwork.coop
      gov.vu
      highwinds.coop
      horizon.coop
      lifelease.ca
      mfamiante.coop
      nwhousing.org.uk
      olan.coop
      olan.homes
      ourcoop.com
      rch.coop
      reseaufuneraire.coop
      reseaufuneraires.coop
      residence-funeraire.coop
      rfc.wales
      rfmaska.coop
      rfu.club
      rumblingbridgehydro.coop
      sheffield.coop
      sunrisefuneral.coop
      uk.com
      webs.com
      weebly.com
      westsolentsolar.coop
      wordpress.com
    ]).freeze
  end
end
