require 'yaml'
require_relative 'utils'

MONITORING_CFG = "monitoring.cfg"

ConfigData  = Struct.new( :id, :description, :source, :sla, :monitor_endpoints, :monitor_connectivity, :monitor_backup, :create_ticket, :reported_alerts, :endpoints ) do
    def initialize(*)
        super
		self.source					||= []
		self.sla					||= []
		self.monitor_endpoints		||= false
		self.monitor_connectivity	||= false
		self.monitor_backup			||= false
		self.create_ticket			||= false
		self.reported_alerts		||= []
    end
	
	def monitoring?
		self.monitor_endpoints || self.monitor_connectivity || self.monitor_backup
	end
end

class MonitoringConfig
attr_reader :config

	def initialize
		if File.file?( MONITORING_CFG )
			@config = YAML.load_file( MONITORING_CFG ) 
		else
			@config = []
		end
	end

	def by_id idx
		result = @config.select{ |cfg| cfg.id.eql?( idx ) }
		result.first if result
	end
	
	def by_description desc
		result = @config.select{ |cfg| cfg.description.upcase.eql?( desc.upcase ) }
		result.first if result
	end

	def delete_entry entry
		@config.delete entry
	end

	def save_config
		FileUtil.write_file( MONITORING_CFG, YAML.dump( @config.sort_by{ |t| t.description.upcase } ) )
	end

	def load_config( source, tenants )
		# add missing tenants config entries
		tenants.each do |t|
			cfg = ConfigData.new( t.id, t.description, [source] ) unless by_description( t.description )
			# not found by descriptio
			if cfg
				# check if we have a record with same id
				if by_id( t.id )
					# overwrite original item
					cfg = by_id( t.id )
					puts "Rename tenant [#{cfg.description}] to [#{t.description}]"
				else
					# not renamed, add it
					puts "Nieuwe tenant [#{t.description}]"
					@config << cfg
				end
			else
				cfg = by_description( t.description )
			end
			cfg.description = t.description
			cfg.source << source unless cfg.source.include? source
			cfg.endpoints = t.endpoints.count if t.endpoints # endpoints can be nil incase no access/unmanaged
		end
		# update config
		save_config
		@config
	end
	
	def report
		keys = [ "CloudAlly", "Skykick", "Sophos", "Veeam" ]
		report_file = "configuration.md"
		File.open( report_file, "w") do |report|
			report.puts "| Company | Ticket | #{keys.join( ' | ' )} |"
			report.puts "|:--|:--:|#{':--: | ' * keys.count}"
			@config.each do |cfg|
				v = {}
				keys.each do |key|
					if cfg.source.include? key
						sla = (cfg.sla.grep /#{key}/).first
						if !sla || sla.empty?
							sla = "*todo*"
						else
							sla = sla.gsub( key + "-", "" )
						end
						v[key] = sla
					else
						v[key] = "-"
					end
				end
				s =  keys.map{|k| "#{v[k]}|"}.join
				report.puts "|#{cfg.description}|#{cfg.create_ticket}|#{s}"
			end
			puts "#{report_file} written"
		end
	end
end

