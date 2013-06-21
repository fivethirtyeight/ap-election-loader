require 'trollop'

dir = "#{File.expand_path(File.dirname(__FILE__))}"
Dir["#{dir}/ap/*.rb"].each {|f| require f }
Dir["#{dir}/posthook/*.rb"].each {|f| require f }

params = Trollop::options do
  opt :states, "Specify comma-separated states to download", :type => :string, :default => nil
  opt :skipstates, "Specify comma-separated states not to download", :default => ''
  opt :interval, "Specify interval (in seconds) at which AP data will be downloaded", :type => :int, :default => nil
  opt :once, "Only download and import data once", :default => false
  opt :import, "Import AP data", :default => true
  opt :delegates, "Import AP delegates (_D files)", :default => false
  opt :clean, "Clean the data directory for these states before downloading", :default => false
  opt :initialize, "Create initial set of results records", :default => false
  opt :finalize, "Publish files without ajax updates", :default => false
  opt :record, "Record this run", :default => false
  opt :replay, "Replay the most recent run", :default => false
  opt :replaydate, "Specify date of replay to run (e.g. 20120521)", :type => :string
end

AP::Crawler.new(dir, params).crawl
