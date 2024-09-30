require 'yaml'
require 'rss'
require 'open-uri'
require_relative 'utils'
require_relative 'MonitoringFeed'


class MonitoringNCSC < MonitoringFeed
	def initialize( config )
    super( config, 'https://advisories.ncsc.nl/rss/advisories', 'NCSC' )
  end
  def high_priority?( item )
    probability = impact = '?'
    # prob/impact medium/high is described as "NCSC-2024-0369 [1.01] [M/H] Kwetsbaarheden verholpen in ..."
    if match = item.title.match(/\[([HML])\/([HM])\]/)
      probability = match[1]
      impact = match[2]
    end
    (probability == 'H' || impact == 'H')
  end
end
