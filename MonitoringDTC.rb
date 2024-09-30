require 'yaml'
require 'rss'
require 'open-uri'
require_relative 'utils'
require_relative 'MonitoringFeed'


class MonitoringDTC < MonitoringFeed
	def initialize( config )
    super( config, 'https://www.digitaltrustcenter.nl/rss.xml', 'DTC' )
  end
  def high_priority?( item )
    ["KRITIEK","ERNSTIG"].any? { |term| item.title.upcase.include? term }
  end
end
