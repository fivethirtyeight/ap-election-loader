# AP Elections Data Loader

Many news organizations use data from The Associated Press to power their election results reporting and real-time interactive maps. The code in this repository has been used by The Huffington Post since the 2012 Iowa caucuses to build result maps for elections including the [Republican primaries](http://elections.huffingtonpost.com/2012/primaries), the [general election](http://elections.huffingtonpost.com/2012/results) and the [Wisconsin recall](http://elections.huffingtonpost.com/2012/wisconsin-recall-results) in 2012 and the special elections in [South Carolina](http://elections.huffingtonpost.com/2013/mark-sanford-vs-elizabeth-colbert-busch-sc1) and [Massachusetts](http://elections.huffingtonpost.com/2013/massachusetts-senate-results) in 2013.

You must have a contract with The Associated Press and an account on its FTP server to use this code.

This repository has a single purpose: to get results off the AP's FTP server and into MySQL as fast as possible. It does not contain methods to query those results, and does not make assumptions about the front-end used to display the loaded data.


## Getting started

Create local copies of the example config files, and enter your AP credentials into `config/ap.yml` and your database credentials into `config/database.yml`:

	cp config/ap.yml.example config/ap.yml
	cp config/database.yml.example config/database.yml

Import the current results data for Massachusetts:

	ruby crawl.rb --initialize --states=MA

The results data from the AP FTP server is now loaded into the `ap_races`, `ap_results` and `ap_candidates` tables in MySQL.

On subsequent imports for the current election in Massachusetts, you do not need to include the `initialize` option:

	ruby crawl.rb --states=MA

The full list of options is described below.

## Replays

The AP conducts tests of its live results reporting in the weeks leading up to an election. With the `record` and `replay` parameters, you can record these tests and replay them at a later time, which is useful for development. Recordings are stored on s3, which means you can make them accessible to other developers.

To record and replay an election test, first create an `s3.yml` config file from the example file provided and fill in your account information.

Start recording an AP test before it begins, and stop it after the test is over:

	ruby crawl.rb --record

Upload the recording to s3:

	ruby upload_replay.rb

Now you can run that replay from any development environment:

	ruby crawl.rb --replay

By default, the newest replay will always be run, but you can change that with the `replaydate` option.

## Posthooks

Posthooks allow you to create code that is run every time new results are imported. For example, at the Huffington Post, we often bake out static pages each time results are updated.

To add a posthook, copy the example file:

	cp posthook/posthook.rb.example posthook/posthook.rb

Each time results have been updated, the `run` method in your posthook will be called. You can add any code you need to that file, and add libraries or other external dependencies to the posthook directory.

## All Options

The following options are available to `crawl.rb`. Any option listed without examples is boolean and defaults to false.

- `states`: Comma-separated states to download
    - examples: `MA`, `MA,CA`, `all`
- `skipstates`: Comma-separated states *not* to download
    - examples: `MA`, `MA,CA`
- `initialize`: Create initial set of results records
- `once`: Only download and import data once
- `clean`: Clean the data directories for specified states before downloading
- `interval`: Interval in seconds at which AP data will be downloaded
    - examples: `300`, `600`
- `record`: Record this run
- `replay`: Replay the most recent run
- `replaydate`: Specify date of replay to run
    - examples: `20130521`, `20130523`
- `help`: Show help dialog

## Authors

- Jay Boice, jay.boice@huffingtonpost.com

## Copyright

Copyright &copy; 2013 The Huffington Post. See LICENSE for details.
