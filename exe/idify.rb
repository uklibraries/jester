#!/usr/bin/env ruby

require 'nokogiri'

input = ARGV[0]
output = ARGV[1]
puts "#{input} -> #{output}"

raw = File.read(input).gsub!(/xmlns="(.*?)"/, '')
raw.gsub!(/c[0-9]{2,2}/, 'c')
xml = Nokogiri::XML(raw)

id = 0
xml.xpath('//c').each do |node|
  id += 1
  node['id'] = "ref#{id}"
end

File.open(output, 'w') do |f|
  f.write xml.to_xml
end
