require 'haml'
require 'json'
require 'nokogiri'
require 'pairtree'
require 'solr_ead'

def subcomponent
  pieces = [
    'c'
  ]
  (1..12).each do |i|
    pieces << "c#{sprintf '%02d', i}"
  end
  pieces.collect {|piece| "/*/#{piece}"}.join('|')
end

# The output of gsub! might be nil
module SolrEad::Behaviors
  def components(file)
    raw = File.read(file)
    raw.gsub!(/xmlns="(.*?)"/, '')
    raw.gsub!(/<c[0-9]{2,2}/, '<c')
    raw.gsub!(/<\/c[0-9]{2,2}/, '<\/c')
    xml = Nokogiri::XML raw
    xml.xpath('//c')
  end

  def prep(node)
    part = Nokogiri::XML(node.to_s.gsub(/\s+/, ' '))
    part.xpath('/*/c').each do |e|
      e.xpath(subcomponent).each do |s|
         s.children.each do |g|
           g.remove
         end
      end
      e.xpath('//container').each do |container|
        type = container['type']
        if type == 'othertype' and container['label']
          container['label'] = container['label'].downcase.strip
        end
        if type
          container['type'] = container['type'].downcase.strip
        end
      end
    end
    return part
  end
end

class ExploreEad < SolrEad::Document
  use_terminology SolrEad::Document

  def component_path
    'c01|c02|c03|c04|c05|c06|c07|c08|c09|c10|c11|c12'
  end
  
  extend_terminology do |t|
    t.author(path: 'filedesc/titlestmt/author')
    t.physloc(path: 'archdesc/did/physloc')
    t.prefercite(path: 'archdesc/prefercite/p')

    t.creator(path: 'archdesc/did/origination/persname')

    t.c01 {
      t.id(path: {attribute: 'id'})
      t.level(path: {attribute: 'level'})
    }
  end
end

class ExploreComponents < SolrEad::Component
  use_terminology SolrEad::Component
end

class FileIndexer < SolrEad::Indexer
  attr_accessor :flat, :options, :top_components
  def initialize opts={}
    self.flat = opts[:flat]
    self.options = opts
    @top_components = []
  end

  def create file
    doc = om_document(File.new(file))
    doc.find_by_xpath('//container').each do |container|
        type = container['type']
        if type == 'othertype' and container['label']
          container['label'] = container['label'].downcase.strip
        end
        if type
          container['type'] = container['type'].downcase.strip
        end
    end
    doc.find_by_xpath('//dsc/c|//dsc/c01').each do |c|
      cs = Nokogiri::XML(c.to_xml)
      cs.xpath(subcomponent).each do |s|
         s.children.each do |g|
           g.remove
         end
      end
      noko = Nokogiri::XML(cs.to_xml)
      noko.xpath('/*').first.name = 'c'
      @top_components << noko
    end
    id = options[:options][:id]
    flat.open("#{id}.xml", 'w') do |f|
      f.write doc.to_xml
    end
    add_components(file) unless options[:simple]
  end

  def update file
    create file
  end

  # Not needed: delete file

  private

  def add_components file, counter = 1
    components(file).each do |node|
      doc = om_component_from_node(node)
      id = [options[:options][:id], node.attr('id')].join('_')
      flat.open("#{id}.xml", 'w') do |f|
        f.write doc.to_xml
      end
      counter += 1
    end
  end
end

module Jester
  class MetadataReader
    def initialize(mets)
      @namespaces = {
        'mets' => 'http://www.loc.gov/METS/',
      }
      @xml = Nokogiri::XML(IO.read mets)
    end

    def repository(mets)
      repositories = @xml.xpath('//mets:agent[@TYPE="REPOSITORY"]/mets:name', @namespaces)
      if repositories.count > 0
        repositories.first.content
      else
        'Unknown repository'
      end
    end

    def get_ead(mets)
      @xml.xpath('//mets:file[@ID="AccessFindingAid"]', @namespaces).each do |node|
        node.xpath('mets:FLocat', @namespaces).each do |flocat|
          return "data/" + flocat['xlink:href']
        end
      end
    end
  end

  def self.idify(input, output)
    raw = File.read(input)
    raw.gsub!(/xmlns="(.*?)"/, '')
    raw.gsub!(/<c[0-9]{2,2}/, '<c')
    raw.gsub!(/<\/c[0-9]{2,2}/, '</c')
    xml = Nokogiri::XML(raw)

    id = 0
    xml.xpath('//c').each do |node|
      id += 1
      node['id'] = "ref#{id}"
    end

    File.open(output, 'w') do |f|
      f.write xml.to_xml
    end
  end

  class LinkPrinter
    def initialize(obj)
      @obj = obj
      @daos = []
      @bucket = {}
      @initialized = false
    end

    def insert_daos_from(xml)
      noko = Nokogiri::XML(xml)
      noko.remove_namespaces!
      noko.xpath('//dao').each do |dao|
        insert_dao(dao['entityref'])
      end
    end

    def insert_dao(dao)
      @daos << dao
    end

    def insert_linkset(linkset)
      unless @initialized
        @daos.each do |dao|
          @bucket[dao] = []
        end
        @pos = 0
        @max = @daos.length - 1
        @initialized = true
      end
      dao = linkset[:dao]
      if @daos.include?(dao) and (dao != @daos[@pos]) and (@pos <= @max)
        @pos += 1
      end
      @bucket[@daos[@pos]] << linkset
    end

    def print
      @bucket.each do |dao, bucket|
        @obj.open("#{dao}.json", 'w') do |f|
          f.write bucket.to_json
        end
      end
    end
  end

  class MetsReader
    def initialize(id, mets, base_url)
      @id = id
      @mets = Nokogiri::XML(IO.read mets)
      @mets.remove_namespaces!
      @file = {}
      @mets.xpath('//file').each do |file|
        use = file['USE']
        use.gsub!(/\s+/, '_')
        flocat = file.xpath('FLocat').first
        href = "#{base_url}/#{@id}/data/#{flocat['href']}"
        @file[file['ID']] = {:use => use, :href => href}
      end
    end

    def linksets
      result = []
      @mets.xpath('//structMap/div[@TYPE="section"]').each do |section|
        section.xpath('div').each do |page|
          linkset = {
            :dao => "#{@id}_#{section['ORDER']}_#{page['ORDER']}",
            :links => {},
          }
          page.xpath('fptr').each do |fptr|
            fileid = fptr['FILEID']
            if @file.has_key?(fileid)
              file = @file[fileid]
              linkset[:links][file[:use]] = file[:href]
            end
          end
          result << linkset
        end
      end
      result
    end
  end
end
