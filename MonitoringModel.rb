
MonitoringIncident = Struct.new( :source, :device, :start_time, :end_time, :alert ) do
	def time_to_s
		if start_time.eql? end_time
			start_time.to_s
		else
			"#{start_time} - #{end_time}"
		end
	end
	def endpoint_to_s
		to_s
	end
	def to_s
		"  #{time_to_s}: #{source} #{alert.severity} alert\n" \
		"   Description: #{alert.description}\n"
	end
end

CustomerAlerts = Struct.new( :name, :alerts, :devices ) do
attr_accessor :customer #hidden field
    def initialize(*)
        super
		@source			= "Unknown"
		self.alerts		||= []
		# default entries have empty hash
		self.devices	||= Hash.new {|hsh, key| hsh[key] = {} }
    end
	def source
		@source
	end
	def add_incident( device, alert, klass )
    # contact alerts for same type together to get start end times
    # TODO: not all systems have alert type
		alert_type = alert.property("type")
		device_alerts = devices[alert.endpoint_id]
		if device_alerts[alert_type] 
			# update end date
			incident = device_alerts[alert_type] 
			incident.end_time = alert.created
		else
			instance = klass.new( device, alert.created, alert.created, alert ) 
			device_alerts[alert_type]  = instance
			@source = instance.source
		end
	end

	def report
		if devices.count > 0
			rpt = "Klant: #{name}\n"
			devices.each do |device_id, incidents|
				endpoint = incidents.values.first.endpoint_to_s
				rpt += "- #{endpoint} (#{device_id})\n"
				incidents.each do |type,incident|
					rpt += incident.to_s + "\n"
				end
			end
		else
			rpt = nil
		end
		rpt
	end
	
	def remove_reported_incidents( reported_alerts )
		orig = reported_alerts
		count = 0
		source = ""
		devices.each do |device_id, incidents|
			orig += incidents.values.map{ |i| "#{i.source}-#{i.alert.id}" }
			incidents.each do |type,incident|
				# backward compatibility, check for reported alerts without prefix
				if reported_alerts.include?( "#{incident.source}-#{incident.alert.id}" ) || reported_alerts.include?( incident.alert.id )
					source = incident.source
					count += 1
					orig.delete( incident.alert.id )
					incidents.delete( type )
				end
			end
			# remove if all incidents have been removed
			devices.delete( device_id ) if ( incidents.count == 0 )
		end
		puts "- #{count} #{source} incident(s) already reported" if count > 0
		orig.uniq
	end
end

class AbstractMonitor
	attr_reader :source

	def initialize( source, client, report, config, log ) 
		@source = source
		@client = client
		@report = report
		@config = config
		@log = log
		@all_alerts = {}
	end
	
	def run all_alerts
		raise NotImplementedError.new("You must implement this method")
	end

	def report_tenants
		FileUtil.write_file( "#{source.downcase}-tenants.json", @client.tenants.to_json )
	end
protected
	def collect_alerts tenant
		result = @client.alerts( tenant.id )
		# return hash of alerts
		result
	end
	def create_endpoint_from_alert( customer, alert )
		device_id = alert.endpoint_id
		endpoint = customer.endpoints[device_id]
		if !endpoint
			# create endpoint from alert
			customer.endpoints[device_id] = endpoint = alert.create_endpoint()
		end
		endpoint
	end
end