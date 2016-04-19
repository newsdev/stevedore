#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'koala'
require 'json'
require 'aws-sdk'
require 'stevedore-uploader'


require 'optparse'
STDOUT.sync = true


# for testing ONLY
$legit_names = [
              "Ted Cruz",
              "George E. Pataki",
              "Rick Santorum",
              "Rick Perry",
              "Donald J. Trump",
              "Carly Fiorina",
              "John Kasich",
              "Bobby Jindal",
              "Scott Walker",
              "Mike Huckabee",
              "Chris Christie",
              "Marco Rubio",
              "Lindsey Graham",
              "Dr. Ben Carson",
              "Rand Paul",
              "Jeb Bush",

              "Martin O'Malley",
              "Lincoln Chafee",
              "Bernie Sanders",
              "Hillary Clinton",
]



module Stevedore
  class FacebookArchiver
    attr_accessor :screen_names, :facebook_access_key

    PLATFORM = "facebook"
    S3_PREFIX = PLATFORM + "_archiver"

    def self.mapping
      {
        platform: {type: :string, index: :not_analyzed},  # e.g. PLATFORM or 'twitter'
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
        link: {type: :string, index: :not_analyzed},
        platform_username: {type: :string, index: :not_analyzed},
        platform_displayname: {type: :string},
        favorite_count: {type: :integer},
        comment_count: {type: :integer},
        updated_at: { type: :date, format: "dateOptionalTime" },

        geo: {type: :geo_point }, # ???


      }
    end

    def initialize(es_host, es_index, s3_bucket)
      @es_host  = es_host
      @es_index = es_index.nil? ?  "social-media" : es_index
      @uploader = Stevedore::ESUploader.new(@es_host, @es_index, nil, nil)
      @uploader.add_mapping(PLATFORM, FacebookArchiver.mapping)

      @limit = 50

      s3 = Aws::S3::Resource.new({ # assumes your keys are in ~/.aws/credentials
        region: 'us-east-1',
      })
      @s3_bucket = s3_bucket
      @bucket = s3.bucket(@s3_bucket)
      # get a shortlived token here  https://developers.facebook.com/tools/explorer
    end

    def update_whom_to_follow!
      # should fetch the Driveshaft version of https://docs.google.com/spreadsheets/d/1v6i0Q28Dco8HqGyAc-DBfWksunpr0LtRnHv0rr4wCZ8/edit#gid=0
      # to end up with a list of accounts on Facebook to follow (or unfollow) and a mapping to the candidate name.
      return @screen_names unless @screen_names.nil?

      resp = open(File.join(File.dirname(__FILE__), 'social_media_accounts.json')){|f| f.read}
      @screen_names = JSON.parse(resp)["Facebook"]
      @screen_names
    end

    def get_newest_post(user_handle)
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
                              updated_at: {
                                order: "desc"
                              }
                            }
                          ]                          
                        }
      tweet = res["hits"]["hits"].first
      tweet.nil? ? nil : tweet["_source"]["created_at"]
    end

    def graph
      @my_graph ||= Koala::Facebook::API.new(@facebook_access_key)
      @my_graph
    end

    def scrape_and_upload!(output_stream=STDOUT)
      posts_by_account(output_stream) do |user, posts|
        posts.reject!{|post| post['from'].nil? }
        next if posts.empty?
        begin
          output_stream.puts "uploading"
          resp = @uploader.bulk_upload_to_es! posts.map{|post| to_es(post, user["candidate_name"], user["handle"].to_s) }.compact, PLATFORM
          output_stream.puts resp.inspect if resp["errors"]
        rescue Manticore::Timeout, Manticore::SocketException => e
          output_stream.puts e.inspect
          output_stream.puts "Upload error: #{e} #{e.message}."
          output_stream.puts e.backtrace.join("\n") + "\n\n\n"
          output_stream.puts("retrying at #{Time.now}")
          retry
        end
        output_stream.puts resp if resp["errors"]
      end
      output_stream.puts "done scraping facebook!"
    end 


    def posts_by_account(output_stream, &blk)
      @screen_names.each do |user|
        user_handle = user["handle"].to_s

        user_info = get_user_info(user_handle)
        user_id = user_info["id"]

        output_stream.puts "getting timeline for #{user_handle}"
        newest_fb_post_time = get_newest_post(user_handle)

        posts = crawl(user_handle)
        posts.reject!{|post|!newest_fb_post_time.nil? && post["updated_time"] < newest_fb_post_time }
        # posts.select!{|post| post['from']['category'] }
        output_stream.puts "Got #{posts.size} new (or newly updated) posts"

        posts.reject! do |post| # remove posts that aren't FROM the person whose page it is.
          post["from"] && post["from"]["id"].to_s != user_id  #&& (puts "rejected: " + post.inspect; true) #Fpost["to"]["data"] && post["to"]["data"].any?{|to| post["id"].include?(to["id"] + "_") }
        end
        posts.reject{|post| $legit_names.include? post["from"]["name"] }.each{|p| puts "included: " +  p.inspect}

        oldest_post = posts.sort_by{|post| post["updated_time"] }.first
        posts.each do |post|
          media_to_s3!(post) if ["photo", "video"].include? post["type"]
        end

        yield user, posts
        output_stream.puts "sleeping, oldest post in this tranche was at #{DateTime.strptime(oldest_post['updated_time'],'%Y-%m-%dT%H:%M:%S %z')}" unless oldest_post.nil?
        sleep 60
      end
    end

    def get_user_info(username)
      begin 
        page = graph.get_object(username, {api_version: "v2.3"})
      rescue JSON::ParserError, Faraday::ConnectionFailed, Koala::Facebook::ServerError, Net::ReadTimeout, Errno::EHOSTUNREACH
        sleep(60)
        retry
      end
      return page
    end


    def crawl(username)
      my_limit = @limit
      begin 
        resp = graph.get_connection(username, "feed", {limit: my_limit, api_version: "v2.3", type: "large"})
      rescue JSON::ParserError, Faraday::ConnectionFailed, Koala::Facebook::ServerError, Net::ReadTimeout, Errno::EHOSTUNREACH => e
        puts "Crawl error: " + e.inspect
        my_limit = my_limit / 2
        sleep(60)
        retry unless my_limit == 1
      end
      return resp
    end

    MEDIA_URL_KEYS = {
      "photo" => "picture",
      "video" => "source"
    }
    def media_to_s3!(post)
      puts "uploading media from `#{post["type"]}`"
      url = post[MEDIA_URL_KEYS[post["type"]]]  #TODO: should I upload thumb AND video for videos, or just the video
      if post["type"] == "photo"
        object_id = post["object_id"] # e.g. 889904464397892
        begin
          image_data = graph.get_object(object_id)
        rescue Faraday::ConnectionFailed, Koala::Facebook::ServerError, Net::ReadTimeout, Errno::EHOSTUNREACH
          sleep(15)
          retry
        end
        max_image = image_data["images"].max_by{|img| img["width"]}
        url = max_image["source"]
        puts "new url: #{url}"
      end

      base_name = url.split('/')[-1].split("?")[0]
      base_name = [post['from']['id'], post['from']['name'].gsub(/[^A-Za-z]/, '_') , DateTime.strptime(post['created_time'],'%Y-%m-%dT%H:%M:%S %z').to_s + base_name].join("_")

      count = 0
      begin
        bytes = Net::HTTP.get(URI(url))
      rescue Faraday::ConnectionFailed, Koala::Facebook::ServerError, Net::ReadTimeout, Errno::EHOSTUNREACH
        sleep(10)
        count += 1
        count > 3 ? return : retry
      end

      # file_path = File.join(save_dir, base_name)
      # #TODO: this should upload to S3.
      # begin
      #   File.open(file_path, 'wb'){ |file| file << bytes }
      # rescue Errno::EHOSTUNREACH
      #   puts "Error, host unreachable, didn't cache: #{url}"
      # end

      s3_path = File.join(S3_PREFIX, base_name)
      post["s3_path"] = "http://s3.amazonaws.com/#{@s3_bucket}/#{s3_path}"

      puts s3_path
      resp = @bucket.put_object(
        body: bytes,
        key: s3_path
      )
      nil
    end

    def to_es(post, candidate_name, candidate_handle)
      puts "No s3_path? #{post.inspect}" if ['video', 'photo'].include?(post['type']) && !post.has_key?("s3_path")
      fb_link = if ['video', 'photo'].include?(post['type']) && post['link'].include?("facebook.com")
                post['link']
              else
                (!post['actions'].nil? ? post['actions'].first['link'] : nil)
              end.to_s

      puts "Youtube link (#{fb_link}): " + post.inspect + "\n" if fb_link.to_s.include?("youtube")
      {
        platform: PLATFORM,
        dw_source: PLATFORM + '_archiver',

        body: post['message'].nil? ? nil : post['message'].to_s,
        candidate_name: candidate_name,
        created_at: DateTime.strptime(post['created_time'],'%Y-%m-%dT%H:%M:%S %z'),
        updated_at: post['updated_time'] ? DateTime.strptime(post['updated_time'],'%Y-%m-%dT%H:%M:%S %z') : DateTime.strptime(post['created_time'],'%Y-%m-%dT%H:%M:%S %z') ,
        platform_id: post['id'],
        id: PLATFORM + post['id'].to_s,
        _id: PLATFORM + post['id'].to_s,
        
        image_path: post['s3_path'],

        platform_username: candidate_handle,
        platform_displayname: post['from']['name'],
        platform_userid: post['from']['id'],
        link: fb_link,
        s3_path: post.has_key?("s3_path") ? post["s3_path"] : nil
        # geo: post['location'] ? post['location'] : nil,
        # geo_placename: post['location'] ? post['location']['name'] : nil,
        # favorite_count: post['likes']['count'], #TODO

      }
    end
  end
end



if __FILE__ == $0
  require 'ostruct'
  options = OpenStruct.new
  OptionParser.new "Usage: facebook_archiver.rb [options]" do |opts|
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
      options.daemonize = v
    end
  end.parse!

  if options.daemonize
    START_HOUR = 9
    START_MINUTE = 30
    WINDOW = 10
    puts "waiting for #{START_HOUR}:#{START_MINUTE.to_s.rjust(2, '0')} "
    while 1
      d = DateTime.now 
      puts "🎸🤠 it's #{d.year}-#{d.month}-#{d.day} #{d.hour}:#{d.minute.to_s.rjust(2, '0')} somewhere 🎸🤠"
      if d.hour == START_HOUR && d.minute >= START_MINUTE && d.minute < (START_MINUTE + WINDOW)
        puts "oh sweet time to do stuff, it's #{d.hour}:#{d.minute.to_s.rjust(2, '0')}"
      archiver = Stevedore::FacebookArchiver.new(options.host, options.index, options.s3bucket)
      archiver.facebook_access_key = ENV["FACEBOOK_ACCESS_KEY"]
      archiver.update_whom_to_follow!
      archiver.scrape_and_upload!
      end
      sleep 60 * WINDOW
    end
  else
    archiver = Stevedore::FacebookArchiver.new(options.host, options.index, options.s3bucket)
    archiver.facebook_access_key = ENV["FACEBOOK_ACCESS_KEY"]
    archiver.update_whom_to_follow!
    archiver.scrape_and_upload!
  end
end
