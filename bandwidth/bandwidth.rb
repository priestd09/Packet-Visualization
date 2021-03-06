require 'csv'
require 'date'
require 'json'

bin_size = 3

begin
    ppFile = ARGV[0]
    pcapRange = ppFile.match(/[0-9]*-[0-9]*/)[0]
rescue
    abort "Must supply preprocessed file on command line."
end
begin
    case ARGV[1]
    when "32"
        key_regex = /.*/
    when "24"
        key_regex = /^[0-9]*\.[0-9]*\.[0-9]*/
    when "16"
        key_regex = /^[0-9]*\.[0-9]*/
    else
        raise ArgumentError
    end
rescue
    abort "Must supply subnet on command line: 16, 24, or 32, got: "+ARGV[1]
end


dat_file = "bandwidth."+pcapRange+".s"+ARGV[1]+".csv"

class Timestamped
# Representes a comparable value with auxillary timestamp data
    include Comparable

    def initialize(val, ts)
        @val = val
        @ts = ts
    end

    attr_accessor :val, :ts

    def <=> (other)
        @val <=> other.val
    end

end

class Bandwidth
# Represents up and dn Timestamped bandwidths
    def initialize(up, dn)
        @up = up
        @dn = dn
    end

    attr_accessor :up, :dn

    def merge(up, dn)
        Bandwidth.new([@up, up].max, [@dn, dn].max)
    end

end

start_time = File.open(ppFile, &:readline)[/^[0-9]*\.[0-9]*/].to_f
counter = start_time
highest_bwidths = Hash.new
highest_bwidths.default = Bandwidth.new(Timestamped.new(0,-1), Timestamped.new(0,-1))
up_h = Hash.new
up_h.default = 0
dn_h = Hash.new
dn_h.default = 0

CSV.foreach(ppFile) do |ts,cap,dir,ip_loc,pt_loc,ip_for,pt_for,proto,len|
    ts = ts.to_f

    if ts > counter + bin_size
        counter += bin_size
        keys = (up_h.keys.concat(dn_h.keys)).uniq!
        keys.each {|key|
            up = Timestamped.new(up_h[key]/bin_size, ts)
            dn = Timestamped.new(dn_h[key]/bin_size, ts)
            highest_bwidths[key] = highest_bwidths[key].merge(up, dn)
        }
        up_h.clear
        dn_h.clear
    end

    key = ip_for[key_regex]
    if dir == "up"
        up_h[key] += len.to_i
    else
        dn_h[key] += len.to_i
    end
end


file = File.open(dat_file, mode="w"){ |file|
    file.puts "ip,up,upt,dn,dnt"
    highest_bwidths.each { |key, val|
        file.puts [key, val.up.val, val.up.ts, val.dn.val, val.dn.ts].join(",")
    }
}
