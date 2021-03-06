require 'csv'
require 'date'
require 'geoip'
require 'json'
require 'set'

bin_size = 3
max_dl = 1500
scale_fac = 3
height = max_dl / scale_fac

begin
    ppFile = ARGV[0]
    pcapRange = ppFile.match(/[0-9]*-[0-9]*/)[0]
rescue
    abort "Must supply preprocessed file on command line."
end

isolateFile = ARGV[1]
if isolateFile
    isolated = File.readlines(isolateFile).each{|s| s.chomp!}
else
    isolated = nil
end


up_file = "up."+pcapRange+".svg"
dn_file = "dn."+pcapRange+".svg"
dat_file = "data."+pcapRange+".json"

start_time = File.open(ppFile, &:readline)[/^[0-9]*\.[0-9]*/].to_f
counter = start_time
geo = GeoIP.new('GeoLiteCity.dat')
last_break = -1
up_cols = []
up_col = [0] * height
dn_cols = []
dn_col = [0] * height
packets = []
up_h = Hash.new
up_h.default = 0
dn_h = Hash.new
dn_h.default = 0
ips = Set.new

CSV.foreach(ppFile) do |ts,cap,dir,ip_loc,pt_loc,ip_for,pt_for,proto,len|
    ts = ts.to_f

    if ts > counter + bin_size
        counter += bin_size

        up_cols << up_col.reverse!
        dn_cols << dn_col.reverse!
        up_col = [0] * height
        dn_col = [0] * height
        entries = Hash.new
        keys = (up_h.keys.concat(dn_h.keys)).uniq!
        if keys
            keys.each do |ip|
                dnl = dn_h[ip]
                upl = up_h[ip]
                entries[ip] = {d: dnl, u: upl}
            end
            packets << entries
            up_h.clear
            dn_h.clear
        end
    end

    if isolated and not isolated.include?(ip_for) then next end

    ips.add(ip_for)
    if dir == "dn"
        dn_col[(len.to_i - 1) / scale_fac] += 1
        dn_h[ip_for] += len.to_i
    else
        up_col[(len.to_i - 1) / scale_fac] += 1
        up_h[ip_for] += len.to_i
    end
end

# use the same color scale for uploads and downloads
vals = (dn_cols.flatten.concat(up_cols.flatten)).sort
z = vals.index{|i|i>2}
n = vals.length - z
p50 = vals[(n*0.50).to_i + z]
p80 = vals[(n*0.80).to_i + z]
p95 = vals[(n*0.95).to_i + z]
cutoffs = [0, 1, 2, p50, p80, p95]
cutoffs_legend = ["0", "1", "2", "≤"+p50.to_s, "≤"+p80.to_s, "≤"+p95.to_s,
                  ">"+p95.to_s]
colors = ["000000", "000045", "0000AD", "009C00", "ADD900", "D98600", "E80000"]

geoIPs = Hash.new
ips.each{|ip| loc = geo.city ip
              if loc && (loc.longitude != 0 || loc.latitude != 0)
                  geoIPs[ip] = [loc.longitude.round(4).to_s,
                                loc.latitude.round(4).to_s]
              end
        }

$stderr.puts

# precondition: cutoffs.length <= colors.length
# precondition: cutoffs is sorted
def mk_svg filename, cols, colors, cutoffs
    width = cols.length
    height = cols[0].length

    File.open(filename, mode="w") { |file|
        file.puts '<?xml version="1.0" standalone="no"?>'
        file.puts '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">'
        file.puts '<svg viewBox = "0 0 '+width.to_s+' '+height.to_s+'" version = "1.1">'
        file.puts '<rect x="0" y="0" width="'+width.to_s+'" height="'+height.to_s+'" fill="#'+colors[0]+'"/>'

        cols.each_with_index do |col, i|
            col.each_with_index do |v, j|
                color = ""
                cutoffs.each_with_index do |cutoff, k|
                    if v <= cutoff
                        color = colors[k]
                        break
                    end
                end
                if color == ""
                    color = colors.last
                end
                if color != colors[0]
                    file.puts '<rect x="'+i.to_s+'" y="'+j.to_s+'" width="1" height="1" fill="#'+color+'"/>'
                end
            end
        end

        file.puts '</svg>'
    }

    # Not exactly portable ...
    # Also try rsvg and ImageMagick convert
    return "/Applications/Inkscape.app/Contents/Resources/bin/inkscape --export-png "+filename.gsub("svg", "png")+" "+filename+";"

end

syscall =  mk_svg up_file, up_cols, colors, cutoffs
syscall << mk_svg(dn_file, dn_cols, colors, cutoffs)

File.open(dat_file, mode="w"){ |file|
    file.puts JSON.fast_generate({start_time: start_time, bin_size: bin_size,
    colors: colors.reverse, cutoffs: cutoffs_legend.reverse, packets: packets,
    geoIPs:geoIPs})
}

#Do this after all other memory has been freed
system(syscall)
