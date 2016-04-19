require 'twitter'
require 'stevedore-uploader'
require 'optparse'
STDOUT.sync = true


module Stevedore
  class TwitterArchiver
    attr_accessor :screen_names, :twitter_consumer_key, :twitter_consumer_secret, :twitter_access_token, :twitter_access_token_secret

    def self.mapping
      {
        platform: {type: :string, index: :not_analyzed},  # e.g. 'facebook' or 'twitter'
        dw_source: {type: :string, index: :not_analyzed},
        deleted: {type: :boolean, index: :not_analyzed},
        body: {
          type: :string, 
          index_options: :offsets, 
          term_vector: :with_positions_offsets,
          store: true,
          fields: {
            snowball: {
              type: :string,
              index: "analyzed",
              analyzer: 'snowball_analyzer' ,
              index_options: :offsets, 
              term_vector: :with_positions_offsets,
            }
          }
        },
        candidate_name: {type: :string, index: :not_analyzed},
        created_at: { type: :date, format: "dateOptionalTime" },
        platform_id: {type: :string, index: :not_analyzed}, # likely unique, but maybe not
        id: {type: :string, index: :not_analyzed}, # used to dedupe, update; composed from platform + platform_id

        geo: {type: :geo_point },
        link: {type: :string, index: :not_analyzed},
        platform_username: {type: :string, index: :not_analyzed},
        platform_displayname: {type: :string},
        favorite_count: {type: :integer},
        retweet_count: {type: :integer},
        source: {type: :string}
      }
    end

    def initialize(es_host, es_index, s3_bucket)
      @es_host  = es_host
      @s3_bucket = s3_bucket # TODO: upload media
      @es_index = es_index.nil? ?  "social-media" : es_index
      @uploader = Stevedore::ESUploader.new(@es_host, @es_index, nil, nil)
      @uploader.add_mapping(:twitter, TwitterArchiver.mapping)
      @newest_tweets = Hash.new(nil)
      @oldest_tweets = Hash.new(nil)
    end

    def update_whom_to_follow!
      # should fetch the Driveshaft version of https://docs.google.com/spreadsheets/d/1v6i0Q28Dco8HqGyAc-DBfWksunpr0LtRnHv0rr4wCZ8/edit#gid=0
      # to end up with a list of accounts on Twitter to follow (or unfollow) and a mapping to the candidate name.
      return @screen_names unless @screen_names.nil?

      resp = open(File.join(File.dirname(__FILE__), 'social_media_accounts.json')){|f| f.read }
      @screen_names = JSON.parse(resp)["Twitter"]
      @screen_names
    end

    def get_newest_tweet_id(user_id)
      res = @uploader.client.search index: @es_index,
                        body: {
                          query: {
                            bool: {
                              must: [
                                {
                                  term: {
                                    platform_userid: user_id,
                                  }
                                },
                                {
                                  term: {
                                    platform: "twitter"
                                  }
                                },
                                {
                                  term: {
                                    dw_source: "twitter_archiver"
                                  }
                                }

                              ]
                            }
                          },
                          size: 1,
                          sort: [
                            {
                              created_at: {
                                order: "desc"
                              }
                            }
                          ]                          
                        }
      tweet = res["hits"]["hits"].first
      tweet.nil? ? nil : tweet["_source"]["platform_id"]
    end
    def get_oldest_tweet_id(user_id)
      res = @uploader.client.search index: @es_index,
                        body: {
                          query: {
                            bool: {
                              must: [
                                {
                                  term: {
                                    platform_userid: user_id,
                                  }
                                },
                                {
                                  term: {
                                    platform: "twitter"
                                  }
                                },
                                # {
                                #   term: {
                                #     dw_source: "twitter_archiver"
                                #   }
                                # }

                              ]
                            }
                          },
                          size: 1,
                          sort: [
                            {
                              created_at: {
                                order: "asc"
                              }
                            }
                          ]
                        }
      tweet = res["hits"]["hits"].first
      tweet.nil? ? nil : tweet["_source"]["platform_id"]
    end

    def newest_tweet_id(user_id)
      return @newest_tweets[user_id] if @newest_tweets[user_id]
      begin
        @newest_tweets[user_id] = get_newest_tweet_id(user_id)
      rescue Elasticsearch::Transport::Transport::Errors::NotFound
        nil
      end
      @newest_tweets[user_id]
    end

    def oldest_tweet_id(user_id)
      return @oldest_tweets[user_id] if @oldest_tweets[user_id]
      begin
        @oldest_tweets[user_id] = get_oldest_tweet_id(user_id)
      rescue Elasticsearch::Transport::Transport::Errors::NotFound
        nil
      end
      @oldest_tweets[user_id]
    end

    def client
      @tw_client ||= Twitter::REST::Client.new do |config|
        config.consumer_key        = @twitter_consumer_key
        config.consumer_secret     = @twitter_consumer_secret
        config.access_token        = @twitter_access_token
        config.access_token_secret = @twitter_access_token_secret
      end

    end

    def tweets_by_account(&blk)
      # deletions have to come from the streaming client (the modified Politwoops client)
      # should loop over @screen_names
      @screen_names.each do |user|
        user_id = user["id"].to_i
        user_handle = user['handle']
        newest_tweet_at_start = newest_tweet_id(user_id)
        loop do 
          opts = {count: 199}
          opts[:since_id] = newest_tweet_at_start unless newest_tweet_at_start.nil?
          opts[:max_id] =   oldest_tweet_id(user_id) unless oldest_tweet_id(user_id).nil?
          puts "getting timeline for @#{user_handle} / #{user_id}, #{opts.inspect}"
          tweets = client.user_timeline(user_handle, opts)
          tweets.each{|t| t.instance_variable_set(:@candidate_name, user['candidate_name']) }

          oldest_tweet = tweets.sort_by{|tw| tw.created_at }.first
          puts "Got #{tweets.size} tweets"
          break if (!oldest_tweet.nil? && oldest_tweet.id == @oldest_tweets[user_id]) || tweets.empty? # if we already have this tweet, then we're at the  beginning
          @oldest_tweets[user_id] = oldest_tweet.id unless oldest_tweet.nil?
          # :since_id (Integer) - Returns results with an ID greater than (that is, more recent than) the specified ID.
          # :max_id (Integer) - Returns results with an ID less than (that is, older than) or equal to the specified ID.
          # :count (Integer) - Specifies the number of records to retrieve. Must be less than or equal to 200.

          yield user_handle, tweets
          puts "sleeping, oldest tweet in this tranche was at #{oldest_tweet.nil? ? 'nil' : oldest_tweet.created_at}"
          sleep 60
        end
      end
    end

    def scrape_and_upload!(output_stream=STDOUT)
      tweets_by_account do |account, tweets|
        next if tweets.empty?

        begin
          output_stream.puts "uploading"
          resp = @uploader.bulk_upload_to_es! tweets.map(&:to_es), :twitter
          output_stream.puts resp.inspect  if resp["errors"]
        rescue Manticore::Timeout, Manticore::SocketException => e
          output_stream.puts e.inspect
          output_stream.puts "Upload error: #{e} #{e.message}."
          output_stream.puts e.backtrace.join("\n") + "\n\n\n"
          output_stream.puts("retrying at #{Time.now}")
          retry
        end

        output_streamputs resp if resp["errors"]
      end
      output_stream.puts "done scraping Twitter"
    end 

  end
end

module Twitter
  class Tweet

    def to_es
      {
        platform: 'twitter',
        dw_source: 'twitter_archiver',
        body: full_text,
        candidate_name: @candidate_name,
        created_at: created_at.strftime('%Y-%m-%dT%H:%M:%S%z') ,
        platform_id: id,
        id: 'twitter' + id.to_s,
        _id: 'twitter' + id.to_s,
        
        link: uri,

        # deleted: false,  # do NOT set this (it might overwrite an actually-deleted tweet gathered by the politwoops client)
        geo: geo? ? geo.coords : nil,

        platform_username: user.screen_name,
        platform_displayname: user.name,
        platform_userid: user.id,
        favorite_count: favorite_count,
        retweet_count: retweet_count,
        source: source.to_s.gsub("<a href=\"http://twitter.com\" rel=\"nofollow\">", '').gsub("</a>", '')
      }
    end
  end
end

if __FILE__ == $0
  require 'ostruct'
  options = OpenStruct.new
  OptionParser.new "Usage: twitter_archiver.rb [options]" do |opts|
    opts.on("-hSERVER:PORT", "--host=SERVER:PORT",
            "The location of the ElasticSearch server") do |host|
      options.host = host
    end

    opts.on("-iNAME", "--index=NAME",
            "A name to use for the ES index (defaults to 'social-media')") do |index|
      options.index = index
    end

    opts.on("-d", "--daemonize", "Run always, only scrape on schedule") do |v|
      options.daemonize = v
    end
  end.parse!

  if options.daemonize
    START_HOUR = 11
    START_MINUTE = 30
    WINDOW = 10
    puts "waiting for #{START_HOUR}:#{START_MINUTE.to_s.rjust(2, '0')} "
    while 1
      d = DateTime.now 
      puts "🎸🤠 it's #{d.year}-#{d.month}-#{d.day} #{d.hour}:#{d.minute.to_s.rjust(2, '0')} somewhere 🎸🤠"
      if d.hour == START_HOUR && d.minute >= START_MINUTE && d.minute < (START_MINUTE + WINDOW)
        puts "oh sweet time to do stuff, it's #{d.hour}:#{d.minute.to_s.rjust(2, '0')}"
        archiver = Stevedore::TwitterArchiver.new(options.host, options.index.nil? ? nil : options.index)
        archiver.twitter_consumer_key = ENV['TWITTER_CONSUMER_KEY']
        archiver.twitter_consumer_secret = ENV['TWITTER_CONSUMER_SECRET']
        archiver.twitter_access_token = ENV['TWITTER_ACCESS_TOKEN']
        archiver.twitter_access_token_secret = ENV['TWITTER_ACCESS_TOKEN_SECRET']
        archiver.update_whom_to_follow!
        archiver.scrape_and_upload!
      end
      sleep 60 * WINDOW
    end
  else
    archiver = Stevedore::TwitterArchiver.new(options.host, options.index.nil? ? nil : options.index)
    archiver.twitter_consumer_key = ENV['TWITTER_CONSUMER_KEY']
    archiver.twitter_consumer_secret = ENV['TWITTER_CONSUMER_SECRET']
    archiver.twitter_access_token = ENV['TWITTER_ACCESS_TOKEN']
    archiver.twitter_access_token_secret = ENV['TWITTER_ACCESS_TOKEN_SECRET']
    archiver.update_whom_to_follow!
    archiver.scrape_and_upload!
  end
end
