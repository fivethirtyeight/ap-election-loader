STDOUT.sync = true

module AP
  class Logger
    def log(str)
      puts "#{Time.now.strftime('%m-%d %H:%M:%S')} - #{str}"
    end
  end
end