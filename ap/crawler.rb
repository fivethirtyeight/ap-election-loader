module AP
  class Crawler

    STATES = ["AK", "AL", "AR", "AZ", "CA", "CO", "CT", "DC", "DE", "FL", "GA", "HI", "IA", "ID", "IL", "IN", "KS", "KY", "LA", "MA", "MD", "ME", "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NE", "NH", "NJ", "NM", "NV", "NY", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VA", "VT", "WA", "WI", "WV", "WY"]
    attr_accessor :dir, :params, :env, :ap_config, :logger, :downloader, :importer, :replayer, :new_files, :updated_states

    def initialize(dir, params)
      @dir = dir
      @params = params
      @env = ENV['RAILS_ENV'] || "development"
      @ap_config = YAML::load(File.open("#{@dir}/config/ap.yml"))

      # Set some defaults from config file
      @params[:interval] = @ap_config['interval'] if @params[:interval].nil?
      @params[:states] = @ap_config['states'] if @params[:states].nil?

      # Determine states to download
      if @params[:skipstates].size > 0
        @params[:states] = STATES - @params[:skipstates].split(",")
      else
        @params[:states] = (@params[:states] == 'all' ? STATES : (STATES & @params[:states].split(",")))
      end

      # Some parameters are dependent on others
      @params[:replay] = true if @params[:replaydate] && @params[:replaydate].size > 0
      @params[:initialize] = true if @params[:replay]
      @params[:once] = true if @params[:initialize] && !@params[:record] && !@params[:replay]

      @logger = AP::Logger.new
      @downloader = AP::Downloader.new(self)
      @importer = AP::Importer.new(self)
      @replayer = AP::Replayer.new(self)
      @replayer.init if @params[:replay]
    end

    def crawl
      while true do
        tm_start = Time.now.to_i

        begin
          @new_files = []
          @updated_states = []

          @params[:replay] ? @replayer.replay_all : @downloader.download_all
          @importer.import_all if @new_files.size > 0
          @replayer.record_all if @new_files.size > 0 && @params[:record]

          if @params[:initialize] && @params[:replay]
            @logger.log "Sleeping at zeroes *************"
            sleep 5
          end
          @params[:initialize] = false if @params[:record] || @params[:replay]
        rescue Exception => e
          @importer.connect if e.to_s.include?('MySQL server has gone away')
          @logger.err e.to_s
        end

        break if @params[:once] || (@params[:replay] && @replayer.done)

        s = @params[:interval] - (Time.now.to_i - tm_start)
        sleep(s < 0 ? 0 : s)
      end
    end

  end
end