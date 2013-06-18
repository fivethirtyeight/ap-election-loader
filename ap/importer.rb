require 'mysql2'
require 'yaml'
require 'digest/md5'

module AP
  class Importer

    def initialize(crawler)
      @crawler = crawler
      @db_config = YAML::load(File.open("#{@crawler.dir}/config/database.yml"))[@crawler.env]
      connect
      set_poll_closings if @crawler.params[:replay]
    end

    def import_all

      if @crawler.params[:import]
        @crawler.logger.log "Started importing"
        @crawler.logger.log "New data in #{@crawler.new_files.map{|file| file.first.split('/').last}.join(', ')}" if @crawler.new_files.size > 0

        test_flag_where = "test_flag #{['internal', 'production'].include?(@crawler.env) ? "= 'l'" : "in ('l', 't')"}"

        @crawler.updated_states.each do |state_abbr|
          @crawler.logger.log "Importing #{state_abbr}"

          import_state(state_abbr, @crawler.new_files.select{|file| file.first.index("#{state_abbr}_")}.first.first)

          if @crawler.params[:initialize]

            election_date = q("select election_date from stage_ap_races limit 1").first["election_date"].strftime("%Y-%m-%d")
            q "start transaction"
            q "delete ap_candidates from ap_candidates inner join ap_results on ap_results.ap_candidate_id = ap_candidates.id inner join ap_races on ap_results.ap_race_id = ap_races.id where ap_races.state_postal = '#{state_abbr}' and ap_races.election_date = '#{election_date}'"
            q "insert into ap_candidates select * from stage_ap_candidates"
            q "delete ap_results from ap_results inner join ap_races on ap_results.ap_race_id = ap_races.id where ap_races.state_postal = '#{state_abbr}' and ap_races.election_date = '#{election_date}'"
            q "insert into ap_results (test_flag, ap_race_id, ap_candidate_id, party, incumbent, vote_count, winner, natl_order) select stage_ap_results.test_flag, concat(date_format(stage_ap_races.election_date, '%y%m'), stage_ap_results.race_county_id), candidate_id, party, incumbent, vote_count, winner, natl_order from stage_ap_results inner join stage_ap_races on stage_ap_results.race_county_id = stage_ap_races.race_county_id"
            q "delete ap_races from ap_races where ap_races.state_postal = '#{state_abbr}' and ap_races.election_date = '#{election_date}'"
            q "insert into ap_races (test_flag, id, race_number, election_date, state_postal, county_number, fips_code, county_name, office_id, race_type_id, seat_number, office_name, seat_name, race_type_party, race_type, office_description, number_of_winners, number_in_runoff, precincts_reporting, total_precincts, last_updated) select test_flag, concat(date_format(election_date, '%y%m'), race_county_id), race_number, election_date, state_postal, county_number, fips_code, county_name, office_id, race_type_id, seat_number, office_name, seat_name, race_type_party, race_type, office_description, number_of_winners, number_in_runoff, precincts_reporting, total_precincts, now() from stage_ap_races"
            q "commit"

          else

            q <<-eos
              update ap_races inner join stage_ap_races on ap_races.id = concat(date_format(stage_ap_races.election_date, '%y%m'), stage_ap_races.race_county_id) set
                ap_races.test_flag = stage_ap_races.test_flag,
                ap_races.race_number = stage_ap_races.race_number,
                ap_races.election_date = stage_ap_races.election_date,
                ap_races.state_postal = stage_ap_races.state_postal,
                ap_races.county_number = stage_ap_races.county_number,
                ap_races.fips_code = stage_ap_races.fips_code,
                ap_races.county_name = stage_ap_races.county_name,
                ap_races.office_id = stage_ap_races.office_id,
                ap_races.race_type_id = stage_ap_races.race_type_id,
                ap_races.seat_number = stage_ap_races.seat_number,
                ap_races.office_name = stage_ap_races.office_name,
                ap_races.seat_name = stage_ap_races.seat_name,
                ap_races.race_type_party = stage_ap_races.race_type_party,
                ap_races.race_type = stage_ap_races.race_type,
                ap_races.office_description = stage_ap_races.office_description,
                ap_races.number_of_winners = stage_ap_races.number_of_winners,
                ap_races.number_in_runoff = stage_ap_races.number_in_runoff,
                ap_races.precincts_reporting = stage_ap_races.precincts_reporting,
                ap_races.total_precincts = stage_ap_races.total_precincts,
                ap_races.last_updated = now()
              where stage_ap_races.#{test_flag_where};
            eos

            q <<-eos
              update ap_results inner join stage_ap_races on ap_results.ap_race_id = concat(date_format(stage_ap_races.election_date, '%y%m'), stage_ap_races.race_county_id) inner join stage_ap_results on stage_ap_races.race_county_id = stage_ap_results.race_county_id and ap_results.ap_candidate_id = stage_ap_results.candidate_id set
                ap_results.test_flag = stage_ap_results.test_flag,
                ap_results.party = stage_ap_results.party,
                ap_results.incumbent = stage_ap_results.incumbent,
                ap_results.vote_count = stage_ap_results.vote_count,
                ap_results.winner = stage_ap_results.winner,
                ap_results.natl_order = stage_ap_results.natl_order
              where stage_ap_results.#{test_flag_where};
            eos

          end
        end
      end

      # Wait to cache new files until they're fully merged so the crawler can be killed between downloading and importing
      @crawler.new_files.each do |file, tm, md5|
        File.open("#{file}.mtime", 'w') {|f| f.write(tm)}
        File.open("#{file}.md5", 'w') {|f| f.write(md5)}
      end

      @crawler.logger.log "Finished importing" if @crawler.params[:import]
    end

    private

    def import_state(state_abbr, first_file)
      state_path = first_file.split('/')[0, first_file.split('/').size - 1].join('/')

      files = [["_Race.txt", "ap_races"], ["_Results.txt", "ap_results"]]
      files += [["_Candidate.txt", "ap_candidates"]] if @crawler.params[:initialize]
      files += [["_Race_D.txt", "ap_district_races"], ["_Results_D.txt", "ap_district_results"]] if @crawler.params[:delegates]

      files.each do |f|
        q("truncate stage_#{f.last}")
        next unless File.exists? "#{state_path}/#{state_abbr}#{f.first}"
        load_data_str = (@crawler.env == 'development') ? "load data infile" : "load data local infile"
        q("#{load_data_str} '#{state_path}/#{state_abbr}#{f.first}' into table stage_#{f.last} fields terminated by ';'")
      end
    end

    def set_poll_closings
      @crawler.params[:states].each do |abbr|
        q "update states set polls_close_at = now() + interval 4 hour + interval #{rand(300)} second where abbr = '#{abbr}'"
      end
    end

    def connect
      @db = Mysql2::Client.new(:host => @db_config["host"], :username => @db_config["username"], :password => @db_config["password"], :database => @db_config["database"])
    end

    def q(sql)
      @db.query(sql)
    end

  end
end