require 'yaml'
require_relative 'utils'

MONITORING_CFG = "monitoring.cfg"

ConfigData  = Struct.new( :id, :description, :source, :sla, :monitor_endpoints, :monitor_connectivity, :monitor_backup, :monitor_dtc, :create_ticket, :notifications, :backup_domain, :last_backup, :reported_alerts, :endpoints ) do
    def initialize(*)
        super
		@touched = false
		self.source       				||= []
		self.sla					        ||= []
		self.monitor_endpoints		||= false
		self.monitor_connectivity	||= false
		self.monitor_backup			  ||= false
		self.monitor_dtc		    	||= false
		self.create_ticket		  	||= false
		self.reported_alerts	  	||= []
		self.notifications		  	||= []
    end
	
	def monitoring?
		self.monitor_endpoints || self.monitor_connectivity || self.monitor_backup || self.monitor_dtc
	end
	
	def touch
		@touched = true
	end
	def untouch
		@touched = false
	end
	def touched?
		@touched
	end
end

class MonitoringConfig
attr_reader :config
alias entries config

	def initialize
		if File.file?( MONITORING_CFG )
			@config = YAML.load_file( MONITORING_CFG ) 
			@config.each{ |c| c.untouch }
		else
			@config = []
		end
	end

	def by_id idx
		result = @config.select{ |cfg| cfg.id.eql?( idx ) }
		first_result result
	end
	
	def by_description desc
		result = @config.select{ |cfg| cfg.description.upcase.eql?( desc.upcase ) }
		first_result result
	end
	
	def delete_entry entry
		@config.delete entry
	end
	
	def compact!
		# remove all unused entries
		@config.select { |cfg| !cfg.touched? }.each do |removed|
			puts " * removed customer #{removed.description}"
		end
		@config = @config.reject { |cfg| !cfg.touched? }
	end

	def save_config
		FileUtil.write_file( MONITORING_CFG, YAML.dump( @config.sort_by{ |t| t.description.upcase } ) )
	end

	def load_config( source, tenants )
		# add missing tenants config entries
		tenants.each do |t|
			cfg = ConfigData.new( t.id, t.description, [source] ) unless by_description( t.description )
			# not found by description
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
		end
		# update config
		@config
	end
	
	def report
		keys = [ "CloudAlly", "Skykick", "Sophos", "Veeam", "Integra365", "Zabbix" ]
		report_file = "configuration.md"
		File.open( report_file, "w") do |report|
			report.puts "| Company | Ticket | Endpoints | Backup | DTC | #{keys.join( ' | ' )} |"
			report.puts "|:--|:--:|:--:|:--:|:--:|#{':--: | ' * keys.count}"
			@config.each do |cfg|
				puts cfg.description
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
						v[key] = ""
					end
				end
				s =  keys.map{|k| "#{v[k]}|"}.join
				create_ticket = monitor_endpoints = monitor_backup = ""
				create_ticket     = "on" if cfg.create_ticket
				monitor_endpoints = "on" if cfg.monitor_endpoints
				monitor_backup    = "on" if cfg.monitor_backup
				monitor_dtc       = "on" if cfg.monitor_dtc
				report.puts "|#{cfg.description}|#{create_ticket}|#{monitor_endpoints}|#{monitor_backup}|#{monitor_dtc}|#{s}"
			end
			puts "- #{report_file} written"
		end
	end
private
	def first_result result
		result.first.touch if result.first
		result.first
	end
end

