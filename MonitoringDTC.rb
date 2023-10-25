require 'yaml'
require 'rss'
require 'open-uri'
require_relative 'utils'

# Monitor changes in rss feed from Digital Trust Center https://www.digitaltrustcenter.nl/
Vulnerability = Struct.new( :feed_item, :companies ) do
	def title
		feed_item.title
	end
	def description
		companies_list = companies.map(&:description).join("\n- ")
		"#{feed_item.link}\n#{feed_item.description.strip}\n Please check following clients wihtin working 72 hours\n- #{companies_list}"
	end
end

DTC_TIMESTAMP = "./monitordtc.yml"
DTC_FEED = 'https://www.digitaltrustcenter.nl/rss.xml'
class MonitoringDTC

	def initialize( config )
		@config = config
		# load feed and check from last item
		if File.file?( DTC_TIMESTAMP )
			@last_time = YAML.load_file( DTC_TIMESTAMP ) 
		else
			@last_time = Time.new( 0 )
		end

		# select companies to monitor for DTC
		@companies = @config.entries.select{ |cfg| cfg.monitor_dtc }
	end

	def get_vulnerabilities_list( since=nil )
		items = {}
		since ||= @last_time

		URI.open( DTC_FEED ) do |rss|
			feed = RSS::Parser.parse( rss, false )

			# compress items based on link (the feed contain duplicates for some reason causinf guid not unique)
			feed.items.sort_by{ |i| i.pubDate }.each do |item|
				items[item.link] = item
			end
			
			FileUtil.write_file( DTC_TIMESTAMP, YAML.dump( items.values.last.pubDate ) )
		end
		vulnerabilities = []
		items.values.each do |item| 
			if item.pubDate > since
				vulnerabilities << Vulnerability.new( item, @companies ) 
			end
		end
		vulnerabilities
	end
end
