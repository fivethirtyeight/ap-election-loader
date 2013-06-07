require 'trollop'

$dir = "#{File.expand_path(File.dirname(__FILE__))}"
Dir["#{$dir}/ap/*.rb"].each {|f| require f }
Dir["#{$dir}/posthook/*.rb"].each {|f| require f }

$l = AP::Logger.new
$env = ENV['RAILS_ENV'] || "development"

$params = Trollop::options do
  opt :states, "Specify comma-separated states to download", :type => :string, :default => nil
  opt :skipstates, "Specify comma-separated states not to download", :default => ''
  opt :interval, "Specify interval (in seconds) at which AP data will be downloaded", :type => :int, :default => nil
  opt :once, "Only download and import data once", :default => false
  opt :import, "Import AP data", :default => true
  opt :delegates, "Import AP delegates (_D files)", :default => false
  opt :initialize, "Create initial set of results records", :default => false
  opt :finalize, "Publish files without ajax updates", :default => false
  opt :record, "Record this run", :default => false
  opt :replay, "Replay the most recent run", :default => false
  opt :replaydate, "Specify date of replay to run (e.g. 20120521)", :type => :string
end

ap_config = YAML::load(File.open("#{$dir}/config/ap.yml"))
$params[:interval] = ap_config['interval'] if $params[:interval].nil?
$params[:states] = ap_config['states'] if $params[:states].nil?

STATES = ["AK", "AL", "AR", "AZ", "CA", "CO", "CT", "DC", "DE", "FL", "GA", "HI", "IA", "ID", "IL", "IN", "KS", "KY", "LA", "MA", "MD", "ME", "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NE", "NH", "NJ", "NM", "NV", "NY", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VA", "VT", "WA", "WI", "WV", "WY"]
if $params[:skipstates].size > 0
  $params[:states] = STATES - $params[:skipstates].split(",")
else
  $params[:states] = ($params[:states] == 'all' ? STATES : (STATES & $params[:states].split(",")))
end

$params[:replay] = true if $params[:replaydate] && $params[:replaydate].size > 0
$params[:initialize] = true if $params[:replay]
$params[:once] = true if $params[:initialize] && !$params[:record] && !$params[:replay]

download = AP::Download.new
import = AP::Import.new
replay = AP::Replay.new
replay.init if $params[:replay]

while true do
  tm_start = Time.now.to_i

  begin
    $new_files = []
    $updated_states = []

    download.download_all unless $params[:replay]
    replay.replay_all if $params[:replay]
    import.import_all if $new_files.size > 0
    replay.record_all if $new_files.size > 0 && $params[:record]

    if $params[:initialize] && $params[:replay]
      $l.log "Sleeping at zeroes *************"
      sleep 5
    end
    $params[:initialize] = false if $params[:record] || $params[:replay]
  rescue Exception => e
    import.connect if e.to_s.include?('MySQL server has gone away')
    $l.log "ERR: #{e.to_s}"
  end

  break if $params[:once] || ($params[:replay] && $replaydone)

  s = $params[:interval] - (Time.now.to_i - tm_start)
  s = 0 if s < 0
  sleep s
end
