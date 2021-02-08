#!/usr/bin/env ruby

require 'nokogiri'

input = ARGV[0]

namespaces = {
  'mets' => 'http://www.loc.gov/METS/',
}

#xmlns:rights="http://www.loc.gov/rights/" 
#xmlns:xlink="http://www.w3.org/1999/xlink" 
#xmlns:lc="http://www.loc.gov/mets/profiles" 
#xmlns:bib="http://www.loc.gov/mets/profiles/bibRecord" 
#xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/" 
#xmlns:mets="http://www.loc.gov/METS/" 
#xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
#OBJID="Knt000239"
#xsi:schemaLocation="http://www.loc.gov/METS/ http://www.loc.gov/standards/mets/mets.xsd http://www.openarchives.org/OAI/2.0/oai_dc/ http://www.openarchives.org/OAI/2.0/oai_dc.xsd"

#raw = File.read(input)
#raw.gsub!(/xmlns="(.*?)"/, '')
#xml = Nokogiri::XML(raw)
xml = Nokogiri::XML(IO.read input)

xml.xpath('//mets:file[@ID="MasterFindingAid"]', namespaces).each do |node|
  node.xpath('mets:FLocat', namespaces).each do |flocat|
    puts "data/" + flocat['xlink:href']
    exit
  end
end
