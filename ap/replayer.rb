require 'aws/s3'
require 'yaml'

module AP
  class Replayer

    attr_accessor :done

    def initialize(crawler)
      @crawler = crawler
      @done = false
    end

    def init
      if ['production', 'internal'].include?(@crawler.env)
        @crawler.logger.err "Can't run replays in production environment"
        exit
      end

      @s3_config = YAML.load_file("#{@crawler.dir}/config/s3.yml")
      connect
      bucket = AWS::S3::Bucket.find(@s3_config['bucket'])
      @crawler.params[:replaydate] = bucket.objects(:prefix => "#{@s3_config['directory']}/").map{|o| o.key.split('/')[1, 1].first}.uniq.sort.last.split('.').first unless @crawler.params[:replaydate]

      local_gzip = "#{@crawler.datadir}/#{@crawler.params[:replaydate]}.tar.gz"
      unless File.exist?(local_gzip)
        puts "Downloading replay from #{@crawler.params[:replaydate]}..."
        s3_object = bucket.objects(:prefix => "#{@s3_config['directory']}/#{@crawler.params[:replaydate]}.tar.gz").first
        File.open(local_gzip, 'w') {|f| f.write(s3_object.value)}
        system "tar -zxvf #{local_gzip} -C #{@crawler.datadir}/"
      end

      @timekeys = Dir.glob("#{@crawler.datadir}/#{@crawler.params[:replaydate]}/*").map{|d| d.split('/').last}.uniq.sort
      @timekey_idx = 0
    end

    def replay
      timekey = @timekeys[@timekey_idx]
      @crawler.logger.log "Started replaying #{timekey}"

      archive_dir = "#{@crawler.datadir}/#{@crawler.params[:replaydate]}/#{timekey}"
      new_states = Dir.glob("#{archive_dir}/*").map{|d| d.split('/').last}.uniq
      new_states = new_states & @crawler.params[:states] if @crawler.params[:states]

      new_states.each do |state_abbr|
        state_dir = "#{@crawler.datadir}/#{state_abbr}"
        system "mkdir -p #{state_dir}"
        state_archive_dir = "#{archive_dir}/#{state_abbr}"
        files = ["#{state_abbr}_Results.txt", "#{state_abbr}_Race.txt", "#{state_abbr}_Candidate.txt"]
        files.each do |file|
          archive_file = "#{state_archive_dir}/#{file.split('/').last}"
          next unless File.exists?(archive_file)
          local_file = "#{state_dir}/#{file.split('/').last}"
          system("cp #{archive_file} #{local_file}")
          @crawler.new_files << [local_file, nil, nil]
        end
        @crawler.updated_states << state_abbr unless @crawler.updated_states.include?(state_abbr)
      end

      @timekey_idx += 1
      @done = true if @timekey_idx >= @timekeys.size
      @crawler.logger.log "Finished replaying"
    end

    def record
      @crawler.logger.log "Started recording"
      dt1 = Time.now.strftime('%Y%m%d')
      dt2 = Time.now.strftime('%H%M%S')
      @crawler.updated_states.each do |state_abbr|
        record_state(state_abbr, @crawler.new_files.select{|file| file.first.index("#{state_abbr}_")}, dt1, dt2)
      end
      @crawler.logger.log "Finished recording"
    end

  private

    def record_state(state_abbr, files, dt1, dt2)
      connect
      archive_dir = "#{@crawler.datadir}/#{dt1}/#{dt2}/#{state_abbr}/"
      system "mkdir -p #{archive_dir}"
      files.each do |file|
        archive_file = "#{archive_dir}#{file.first.split('/').last}"
        system "cp #{file.first} #{archive_file}"
      end
    end

    def connect
      AWS::S3::Base.establish_connection!(:access_key_id => @s3_config['access_key_id'], :secret_access_key => @s3_config['secret_access_key'])
    end

  end
end
