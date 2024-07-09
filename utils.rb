require 'json'

# monkeypatch
class Struct
	def to_json options={}
		to_h.to_json
	end
	# get nested json value using object notation a.b.c.value
	def property p
		if self.raw_data
			item = self.raw_data
			p.split( '.' ).each do |o|
				item = item[o] if item
			end
			item.to_s
		else
			""
		end
	end
end

class FileUtil
	def self.write_file( file_name, content )
		File.open( file_name, "w") do |f|
			f.puts( content )
		end
	end
	def self.timestamp
		"#{Time.now.strftime('%Y-%m-%d')}"
	end
	def self.daily_file_name( file_name )
		ext = File.extname( file_name )
		file_name[ext] = "-#{timestamp}#{ext}"
		file_name
	end
	def self.daily_module_name( object )
		self.daily_file_name( object.class.name.split( "::" ).first.downcase + ".log" )
	end
end

class Enum
  def self.enum(array, proc=:to_s)
    array.each do |c|
      const_set c.upcase,c.send(proc)
    end
  end
end
