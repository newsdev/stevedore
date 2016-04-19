#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# based on https://github.com/rarcega/instagram-scraper

require 'instagram'
require 'json'
require 'aws-sdk'
require 'stevedore-uploader'
require 'optparse'
require 'net/http'
require 'net/https'

STDOUT.sync = true


module Stevedore
  class InstagramArchiver
    PLATFORM = 'instagram'
    S3_PREFIX = PLATFORM + "_archiver"
    attr_accessor :screen_names
    def self.mapping
      {
        platform: {type: :string, index: :not_analyzed},  # e.g. 'facebook' or 'twitter'
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
        
        s3_path: {type: :string, index: :not_analyzed},
        geo: {type: :geo_point },
        link: {type: :string, index: :not_analyzed},
        platform_username: {type: :string, index: :not_analyzed},
        platform_displayname: {type: :string},
        favorite_count: {type: :integer},
      }
    end

    def initialize(es_host, es_index, s3_bucket)
      @es_host  = es_host
      @es_index = es_index.nil? ?  "social-media" : es_index
      @uploader = Stevedore::ESUploader.new(@es_host, @es_index, nil, nil)
      @uploader.add_mapping(PLATFORM, InstagramArchiver.mapping)

      s3 = Aws::S3::Resource.new({ # assumes your keys are in ~/.aws/credentials
        region: 'us-east-1',
      })
      @s3_bucket = s3_bucket
      @bucket = s3.bucket(@s3_bucket)
    end

    def update_whom_to_follow!
      # should fetch the Driveshaft version of https://docs.google.com/spreadsheets/d/1v6i0Q28Dco8HqGyAc-DBfWksunpr0LtRnHv0rr4wCZ8/edit#gid=0
      # to end up with a list of accounts on Instagram to follow (or unfollow) and a mapping to the candidate name.
      return @screen_names unless @screen_names.nil?

      resp = open(File.join(File.dirname(__FILE__), 'social_media_accounts.json')){|f| f.read}
      @screen_names = JSON.parse(resp)["Instagram"]
      @screen_names
    end

    def get_newest_insta(user_handle)
      res = @uploader.client.search index: @es_index,
                        body: {
                          query: {
                            bool: {
                              must: [
                                {
                                  term: {
                                    platform_username: user_handle,
                                  }
                                },
                                {
                                  term: {
                                    platform: PLATFORM
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
      tweet.nil? ? nil : tweet["_source"]["created_at"]
    end

    def scrape_and_upload!(output_stream=STDOUT)
      posts_by_account do |user, instas|
        next if instas.empty?
        begin
          output_stream.puts "uploading"
          resp = @uploader.bulk_upload_to_es! instas.map{|insta| to_es(insta, user["candidate_name"]) }, PLATFORM
          output_stream.puts resp.inspect if resp["errors"]
        rescue Manticore::Timeout, Manticore::SocketException => e
          output_stream.puts e.inspect
          output_stream.puts "Upload error: #{e} #{e.message}."
          output_stream.puts e.backtrace.join("\n") + "\n\n\n"
          output_stream.puts("retrying at #{Time.now}")
          retry
        end
        output_stream.puts resp if resp["errors"]
        resp
      end
      output_stream.puts "done scraping Instagram"
    end 

    def posts_by_account(&blk)
      @screen_names.shuffle.each do |user|
        user_handle = user["handle"].to_s
        user_id = user["id"].to_s
        puts "getting timeline for #{user_handle}"
        newest_insta_time = get_newest_insta(user_handle)
        instas = crawl(user_handle, [], nil, newest_insta_time.nil? ? 0 : Time.iso8601(newest_insta_time).to_i)
        puts "Got #{instas.size} instas"


        oldest_insta = instas.sort_by{|insta| insta["created_time"] }.first
        instas.each do |insta|
          image_to_s3!(insta)
        end

        yield user, instas
        # puts "sleeping, oldest insta in this tranche was at #{DateTime.strptime(oldest_insta['created_time'],'%s')}" unless oldest_insta.nil?
        sleep 60
      end
    end


    def crawl(username, items=[], max_id=nil, min_time=0)
      url   = 'https://www.instagram.com/' + username + '/media/' + (max_id.nil? ? '' : "?&max_id=#{max_id}" )
      puts url.inspect
      begin 
        resp = Net::HTTP.get(URI(url))
        media = JSON.load(resp)
        puts media.inspect
        media = {"items" => []} if media.nil?
      rescue JSON::ParserError
        sleep(60)
        retry
      end

      items_to_add = media["items"]
      items_to_add.reject!{|insta| insta["created_time"].to_i <= min_time } 
      return items if items_to_add.empty?

      items += items_to_add

      return items unless media.has_key?('more_available') && media['more_available']
      max_id = media["items"][-1]['id']
      return crawl(username, items, max_id, min_time)
    end

    def image_to_s3!(insta)
      url = insta[insta['type'] + 's']['standard_resolution']['url'].gsub("https://", "http://")
      base_name = url.split('/')[-1]
      base_name = insta['user']['username'] + "_" + DateTime.strptime(insta['created_time'],'%s').to_s + "_" + base_name
      begin
        bytes = Net::HTTP.get(URI(url))
      rescue Errno::ECONNRESET, Errno::EHOSTUNREACH
        retry
      end



      # file_path = File.join(save_dir, base_name)
      # #TODO: this should upload to S3.
      # begin
      #   File.open(file_path, 'wb'){ |file| file << bytes }
      # rescue Errno::EHOSTUNREACH
      #   puts "Error, host unreachable, didn't cache: #{url}"
      # end

      s3_path = File.join(S3_PREFIX, base_name)
      insta["s3_path"] = "http://s3.amazonaws.com/" + @s3_bucket + "/" + s3_path

      @bucket.put_object(
        body: bytes,
        key: s3_path
      )
      nil
    end

    def to_es(insta, candidate_name)
      {
        platform: PLATFORM,
        dw_source: PLATFORM + 'archiver',
        body: insta['caption'].nil? ? '' : insta['caption']['text'],
        candidate_name: candidate_name,
        created_at: DateTime.strptime(insta['created_time'],'%s'),
        platform_id: insta['id'],
        id: PLATFORM + insta['id'].to_s,
        _id: PLATFORM + insta['id'].to_s,
        indexed_at: DateTime.now,

        link: insta['link'],
        s3_path: insta['s3_path'],

        # deleted: false,  # do NOT set this (it might overwrite an actually-deleted tweet gathered by the politwoops client)
        geo: insta['location'] && insta['location']['latitude'] ? [insta['location']['longitude'], insta['location']['latitude']] : nil,
        geo_placename: insta['location'] ? insta['location']['name'] : nil,

        platform_username: insta['user']['username'],
        platform_displayname: insta['user']['full_name'],
        platform_userid: insta['user']['id'],
        favorite_count: insta['likes']['count'],
      }
    end
  end
end

if __FILE__ == $0
  require 'ostruct'
  options = OpenStruct.new
  OptionParser.new "Usage: instagram_archiver.rb [options]" do |opts|

    opts.on("-hSERVER:PORT", "--host=SERVER:PORT",
            "The location of the ElasticSearch server") do |host|
      options.host = host
    end

    opts.on("-iNAME", "--index=NAME",
            "A name to use for the ES index (defaults to 'social-media')") do |index|
      options.index = index
    end

    opts.on("-bPATH", "--s3bucket=PATH",
            "The s3 bucket to upload media files to."
      ) do |s3bucket|
      options.s3bucket = s3bucket
    end


    opts.on("-d", "--daemonize", "Run always, only scrape on schedule") do |v|
      options[:daemonize] = v
    end
  end.parse!

  if options[:daemonize]
    START_HOUR = 10
    START_MINUTE = 30
    WINDOW = 10
    puts "waiting for #{START_HOUR}:#{START_MINUTE.to_s.rjust(2, '0')} "
    while 1
      d = DateTime.now 
      puts "🎸🤠 it's #{d.year}-#{d.month}-#{d.day} #{d.hour}:#{d.minute.to_s.rjust(2, '0')} somewhere 🎸🤠"
      if d.hour == START_HOUR && d.minute >= START_MINUTE && d.minute < (START_MINUTE + WINDOW)
        puts "oh sweet time to do stuff, it's #{d.hour}:#{d.minute.to_s.rjust(2, '0')}"
        archiver = Stevedore::InstagramArchiver.new(options.host, options.index, options.s3bucket)
        archiver.update_whom_to_follow!
        archiver.scrape_and_upload!
      end
      sleep 60 * WINDOW
    end
  else
    archiver = Stevedore::InstagramArchiver.new(options.host, options.index, options.s3bucket)
    archiver.update_whom_to_follow!
    archiver.scrape_and_upload!
  end
end
