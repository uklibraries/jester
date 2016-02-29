#!/usr/bin/env ruby
# Copyright (C) 2016 Michael Slone
# License: MIT

# TODO: Get a better way to do this.
libdir = File.expand_path File.join(File.dirname(__FILE__), 'lib')
$LOAD_PATH.unshift libdir unless $LOAD_PATH.include? libdir

require 'logger'
$logger = Logger.new(STDOUT)
$logger.level = Logger::INFO
$logger.formatter = proc do |severity, datetime, progname, msg|
    "jester [#{datetime}]: #{msg}\n"
end

def say(message)
    $logger.info(message)
end

dir = File.expand_path File.dirname(__FILE__)
lockfile = File.join dir, 'tmp', 'jester.lock'
say "acquiring lock"
if File.new(lockfile, 'w').flock( File::LOCK_NB | File::LOCK_EX )
    say "lock acquired"
else
    say "failed to acquire lock, exiting"
    exit
end

require 'fileutils'
require 'find'
require 'jester'
require 'pairtree'
require 'parallel'

inbox = File.join dir, 'inbox'
todo = File.join dir, 'todo'
success = File.join dir, 'success'
failure = File.join dir, 'failure'
work = File.join dir, 'work'

Find.find(inbox) do |path|
    if File.file? path
        FileUtils.mv path, todo
    end
end

jobs = []
Find.find(todo) do |path|
    if File.file? path
        jobs << File.basename(path)
    end
end

say "queued #{jobs.count} jobs"

dipdir = '/opt/shares/library_dips_1'
diptree = Pairtree.at(dipdir, :create => false)

outdir = File.join dir, 'xml'
outtree = Pairtree.at(outdir, :create => true)

Parallel.each(jobs) do |id|
    say "processing #{id}"
    obj = diptree.get(id)
    mets = File.join obj, 'data', 'mets.xml'
    raw_eadfile = File.join(obj, Jester::get_ead(mets))
    say "ead: #{raw_eadfile}"
    eadfile = File.join(work, "#{id}.xml")
    say "ead: #{raw_eadfile} -> #{eadfile}"
    Jester::idify(raw_eadfile, eadfile)
    todofile = File.join todo, id
    begin
      xml = IO.read(eadfile)
      ead = ExploreEad.from_xml(xml)
      components = ExploreComponents.from_xml(xml)
      obj = outtree.mk(id)
      indexer = FileIndexer.new({
        flat: obj,
        options: {document: ExploreEad, component: ExploreComponents, id: id},
      })
      say "splitting #{id}"
      indexer.create(File.new(eadfile, 'r'))
      say "writing header for #{id}"
      obj.open('header.xml', 'w') do |f|
        f.write Haml::Engine.new(File.read("haml/header.haml")).render(Object.new, {:ead => ead, :components => indexer.top_components})
      end
      FileUtils.mv todofile, success
    rescue Exception => e
      STDERR.puts e.inspect
      FileUtils.mv todofile, failure
    end
end
