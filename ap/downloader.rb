require 'net/ftp'
require 'fileutils'
require 'timeout'
require 'digest/md5'

module AP
  class Downloader

    def initialize(crawler)
      @crawler = crawler
    end

    def download_all
      @crawler.logger.log "Started downloading"
      connect
      @crawler.params[:states].each{|state| download_state(state)}
      disconnect
      @crawler.logger.log "Finished downloading"
    end

  private

    def connect
      begin
        @ftp = Net::FTP.new(@crawler.ap_config['host'])
      rescue Exception => e
        @ftp = Net::FTP.new(@crawler.ap_config['host'])
      end
      @ftp.login(@crawler.ap_config['user'], @crawler.ap_config['pass'])
      @ftp.passive = true
    end

    def disconnect
      @ftp.close
    end

    def download_state(state)
      ftp_dir = "/#{state}/dbready"
      local_dir = "#{@crawler.dir}/data/#{state}"

      FileUtils.makedirs(local_dir) unless File.exists?(local_dir)

      files = ["#{state}_Results.txt", "#{state}_Race.txt"]
      files += ["#{state}_Candidate.txt"] if @crawler.params[:initialize]
      files += ["#{state}_Results_D.txt", "#{state}_Race_D.txt"] if @crawler.params[:delegates]

      download_files(files, ftp_dir, local_dir, state)
    end

    def download_files(files, ftp_dir, local_dir, state)
      files.each do |file|
        local_file = "#{local_dir}/#{file}"

        begin
          timeout(20) do
            old_tm = File.exists?("#{local_file}.mtime") ? File.read("#{local_file}.mtime") : nil
            new_tm = @ftp.mtime("#{ftp_dir}/#{file}").to_i.to_s
            next if new_tm == old_tm

            @ftp.getbinaryfile("#{ftp_dir}/#{file}", "#{local_file}", 1024)

            old_md5 = File.exists?("#{local_file}.md5") ? File.read("#{local_file}.md5") : nil
            new_md5 = Digest::MD5.hexdigest(File.read(local_file))
            next if old_md5 == new_md5

            @crawler.new_files << [local_file, new_tm, new_md5]
            @crawler.updated_states << state unless @crawler.updated_states.include?(state)
          end
        rescue Exception, Timeout::Error => e
          if !e.to_s.include?("The system cannot find the file")
            @crawler.logger.err "FTP ERR for #{ftp_dir}/#{file}: #{e.to_s}"
            FileUtils.rm_f("#{local_dir}/#{file}")
            disconnect
            connect
          end
        end
      end
    end

  end
end
