#!/usr/bin/env ruby
require 'haml'
require 'optimist'
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
    raw.gsub!(/c[0-9]{2,2}/, 'c')
    xml = Nokogiri::XML raw
    xml.xpath('//c')
  end

  def prep(node)
    part = Nokogiri::XML(node.to_s.gsub(/\s+/, ' '))
    #return part
    part.xpath('/*/c').each do |e|
      #cs = Nokogiri::XML(c.to_xml)
      #cs.xpath(subcomponent).each do |s|
      #   s.children.each do |g|
      #     g.remove
      #   end
      #end
      e.xpath(subcomponent).each do |s|
         #s.xpath(subcomponent).each do |g|
         s.children.each do |g|
           g.remove
         end
      end
      
      #{|s| s.remove}
      
      #e.children.each {|s| s.remove}
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
    doc.find_by_xpath('//dsc/c|//dsc/c01').each do |c|
      cs = Nokogiri::XML(c.to_xml)
      cs.xpath(subcomponent).each do |s|
         s.children.each do |g|
           g.remove
         end
      end
      #c.xpath(subcomponent).each {|s| s.remove}
      #c.children.each {|s| s.remove}
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

opts = Optimist::options do
  opt :identifier, "Identifier of EAD", :type => :string
  opt :ead, "Path to EAD", :type => :string
  opt :xml, "Path to XML directory", :type => :string
end

xml = IO.read(opts[:ead])
ead = ExploreEad.from_xml(xml)
components = ExploreComponents.from_xml(xml)
id = opts[:identifier]
tree = Pairtree.at(opts[:xml], :create => true)
obj = tree.mk(id)
indexer = FileIndexer.new({
  flat: obj,
  options: {document: ExploreEad, component: ExploreComponents, id: id},
})

indexer.create(File.new(opts[:ead]))

obj.open('header.xml', 'w') do |f|
  f.write Haml::Engine.new(File.read("haml/header.haml")).render(Object.new, {:ead => ead, :components => indexer.top_components})
end

