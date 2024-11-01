require "date"
require_relative 'MonitoringConfig'


Interval = Struct.new( :description, :days ) do
	def code
		# return first character
		description[0]
	end
	
	def is_due? date
		(Date.today - date).to_i >= days
	end
end

ONCE = Interval.new( "Once", 0 )
WEEKLY = Interval.new( "Weekly", 7 )
MONTHLY = Interval.new( "Monthly", 30 )
BIMONTHLY = Interval.new( "Bi-Monthly", 61 )
QUARTERLY = Interval.new( "Quarterly", 91 )
HALF_YEARLY = Interval.new( "Halfyearly", 182 )
YEARLY = Interval.new( "Yearly", 365 )

INTERVALS = {
	ONCE.code => ONCE,
	WEEKLY.code => WEEKLY,
	MONTHLY.code => MONTHLY,
	BIMONTHLY.code => BIMONTHLY,
	QUARTERLY.code => QUARTERLY,
	HALF_YEARLY.code => HALF_YEARLY,
	YEARLY.code => YEARLY
}
CODES = INTERVALS.keys

Notification = Struct.new( :task, :interval, :triggered ) do
	def to_s
		i = INTERVALS[interval]
		if i
			if ONCE == i
				time_desc = "after date"
			else
				time_desc = "last time triggered"
			end
			"Task '#{task}' to be executed #{i.description}; #{time_desc} #{triggered}"
		else
			"Notification #{task}, invalid interval='#{interval}', triggered=#{triggered}"
		end
	end
  
  def to_s
    "Notification '#{task}', executed #{INTERVALS[interval].description}, last triggered=#{triggered}"
  end
end
PeriodicalNotification = Struct.new( :config, :notification, :interval, :description ) 

class MonitoringSLA

	def initialize( config )
		@config = config
	end
	
	def add_interval_notification customer, text, interval, date=nil
		cfg = @config.by_description customer
		if cfg
			if CODES.include? interval
				if date && !date.empty?
					begin
						d = Date.parse( date )
					end
				else
					d = nil
				end
				n = Notification.new( text, interval, d )
				cfg.notifications << n
				cfg.create_ticket = true
				puts "Notification added: #{n.to_s}"
				@config.save_config
			else
				puts "- '#{interval}' is not a valid interval, please use #{CODES.join(', ')}"
			end
		else
			puts "- customer '#{customer}' not found in configuration"
		end
	rescue ArgumentError # assume date parsing issue
		puts "- '#{date}' is not a valid date"
	end
	def get_periodic_alerts
    result = []

		@config.entries.each do |cfg|
      cfg.notifications ||= [] 
      cfg.notifications.each do |n|
        if CODES.include? n.interval
          interval = INTERVALS[n.interval]
          # quarter is approx 91 days
          if n.triggered.nil? || interval.is_due?( n.triggered )
            result << PeriodicalNotification.new( cfg, n, interval, n.to_s ) 
            n.triggered = Date.today
            # check if once is triggered and remove it
            if ONCE.code.eql? n.interval
              n.interval = "X"
            end
          end
        end
      end
      cfg.notifications.delete_if {|n| n.interval == "X" } 
    end
    result
	end
  def report
    @config.entries.each do |cfg|
      if cfg.notifications && cfg.notifications.count > 0
        puts cfg.description
        cfg.notifications.each do |n|
          puts "- #{n}"
        end
      end
    end
  end
end
