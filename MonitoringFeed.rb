require 'yaml'
require 'rss'
require 'open-uri'
require_relative 'utils'

# Monitor changes in rss feed from Digital Trust Center https://www.digitaltrustcenter.nl/
Vulnerability = Struct.new( :feed_item, :companies, :high_priority? ) do
	def title
		feed_item.title
	end
	def description
		companies_list = companies.map(&:description).join("\n- ")
		"#{feed_item.title}\n#{feed_item.link}\n\n*** Controleer de klanten met een SLA en onderneem aktie binnen 72 uur (3 werkdagen)\n- #{companies_list}"
	end
end

class MonitoringFeed
  attr_reader :source
	def initialize( config, feed, feedcache, source )
		@config = config
    @feed = feed
    @feedcache = feedcache
    @source = source
		# load feed and check from last item
		@last_time = Time.new( 0 )
		if File.file?( feedcache )
			@alerts = YAML.load_file( feedcache ) 
		else
			@alerts = []
		end

		# select companies to monitor for DTC
		@companies = @config.entries.select{ |cfg| cfg.monitor_dtc }
	end

	def get_vulnerabilities_list( since=nil )
		items = {}
		since ||= @last_time

		URI.open( @feed ) do |rss|
			feed = RSS::Parser.parse( rss, false )

			# compress items based on link (the feed contain duplicates for some reason causing guid not unique)
			feed.items.sort_by{ |i| i.pubDate }.each do |item|
				items[item.link] = item unless items[item.link]
			end
			
		end
		vulnerabilities = []
		items.values.each do |item| 
			guid = item.link
			if !@alerts.include? guid
				@alerts << guid
				if item.pubDate > since
					vulnerabilities << Vulnerability.new( item, @companies, high_priority?( item ) ) 
				end
			end
		end
		FileUtil.write_file( @feedcache, YAML.dump( @alerts ) )
		vulnerabilities
	end
  
  def high_priority?( item )
    false
  end
end
