STDOUT.sync = true

module AP
  class Logger

    def log(str)
      puts "#{Time.now.strftime('%m-%d %H:%M:%S')} - #{str}"
    end

    def err(str)
      log("ERROR: " + str)
    end

  end
end