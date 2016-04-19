require 'sinatra'
require 'ostruct'
require 'json'

set :public_folder, File.join(File.dirname(__FILE__), '/../lib')
set logs: StringIO.new('', 'r+')

$node = nil
 
# Remember, these URLs are actually /upload/'
get '/' do
  erb :uploader
end

get '/socmed' do
  erb :social_media_scraper
end

post '/do' do 
  invalid = []

  es_index =  params["index-name"]
  invalid << ["index-name", params["index-name"]] if es_index.nil? || es_index.empty?


  # if the files are already on S3, extract the bucket name from params["files"]
  # if they're not, extract the bucket name from params["frontend-location"] 
  folder = params["files"]
  s3path = params["files"].gsub(/s3:\/\//i, '').split("/", 2).last

  if params["local"] == "local"
    es_host = "localhost:9200"
    is_local = true
    no_front_end = true
  else
    # get the bucket where we're going to put the search frontend's files
    frontend_location = params["frontend-location"]
    frontend_s3_bucket = frontend_location.gsub(/s3:\/\//i, '').split("/", 2).first
    invalid << ['frontend-location', params["frontend-location"]] if frontend_s3_bucket.nil? || frontend_s3_bucket.empty?

    es_host = params["es-host"]
    is_local = false
    invalid << ['es-host', params["es-host"]] if es_host.nil?
  end


  puts "Invalid: #{invalid.inspect}"
  halt JSON.dump({success: false, invalid: invalid}) unless invalid.empty?
  
  filetype = params["filetype"] == "OTHER" ? params["other-filetype"] : params["filetype"] 
  require 'stevedore-uploader'
  require_relative './lib/frontend-uploader'

  begin
    f = Stevedore::ESUploader.new(es_host, es_index, s3_bucket, s3path)
    f.do! folder, settings.logs

  rescue StandardError => e
    halt JSON.dump({success: false, error: e.message + "\n" + e.backtrace.join("\n") })
  end


  if f.errors.size > 0  
    settings.logs.puts "#{f.errors.size} failed documents:"
    settings.logs.puts f.errors.inspect 
  end

  # TODO needs work
  settings.logs.puts "Finished uploading documents at #{Time.now}"

  if (!options.no_front_end) || !options.frontend_location.nil?
    frontend_uploader = Stevedore::FrontendUploader.new(es_host, es_index, frontend_s3_bucket, FRONTEND_S3_PATH)
    settings.logs.puts "Uploading front end"
    frontend_uploader.upload_front_end({
            "index_name" => es_index,
            "name" => params["index-title"].to_s,
            "private?" => "FALSE",
            "data_type" => filetype.empty? ? "blob" : filetype,
            "description" => params["index-description"].to_s
    }) unless OPTIONS.no_front_end
    puts "Finished uploading frontend at #{Time.now}"
    frontend_s3_basepath = "https://#{frontend_s3_bucket}.s3.amazonaws.com/#{FRONTEND_S3_PATH}"
    puts "Uploaded to #{es_index}; go check out the search engine at: \n #{File.join(frontend_s3_basepath.gsub("https:", 'http:'), "/stevedore/search.html##{es_index}")}\n "
  end

  settings.logs.puts "Created Stevedore for #{es_index}; go check out https://stevedore.newsdev.net/search/#{es_index} or http://stevedore.adm.prd.newsdev.nytimes.com/search/#{es_index}"  

  if params["local"] != "local"
    frontend_url = File.join(FRONTEND_S3_BASEPATH.gsub("https:", 'http:'), "/stevedore/search.html?first&template=#{filetype.empty? ? "blob" : filetype}##{es_index}")
    settings.logs.puts "Uploaded to #{es_index}; go check out the search engine at: \n #{frontend_url}\n "
  else
    frontend_url = "/search.html?first&template=#{filetype.empty? ? "blob" : filetype}##{es_index}"
  end
  settings.logs.flush
  JSON.dump({success: true, frontend_url: frontend_url})
end

post '/archive' do 
  invalid = []

  params["index-name"]
  invalid << ["index-name", params["index-name"]] if params["index-name"].nil? || params["index-name"].empty?

  # if the files are already on S3, extract the bucket name from params["files"]
  # if they're not, extract the bucket name from params["frontend-location"] 
  twitter_handles = params["twitter"].split("\n").map{|l| components = l.split(":").map(&:strip); {"candidate_name" => components[0...-1].join(":"), "handle" => components[-1]} }.flatten
  facebook_handles = params["facebook"].split("\n").map{|l| components = l.split(":").map(&:strip); {"candidate_name" => components[0...-1].join(":"), "handle" => components[-1]} }.flatten
  instagram_handles = params["instagram"].split("\n").map{|l| components = l.split(":").map(&:strip); {"candidate_name" => components[0...-1].join(":"), "handle" => components[-1]} }.flatten

  frontend_and_media_location = params["frontend-location"]
  frontend_s3_bucket = frontend_and_media_location.gsub(/s3:\/\//i, '').split("/", 2).first
  invalid << ['frontend-location', params["frontend-location"]] if frontend_s3_bucket.nil? || frontend_s3_bucket.empty?

  if params["local"] == "local"
    es_host = "localhost:9200"
    is_local = true
    no_front_end = true
  else
    # get the bucket where we're going to put the search frontend's files
    es_host = params["es-host"]
    is_local = false
    invalid << ['es-host', params["es-host"]] if es_host.nil?
  end


  puts "Invalid: #{invalid.inspect}"
  halt JSON.dump({success: false, invalid: invalid}) unless invalid.empty?
  
  filetype = params["filetype"] == "OTHER" ? params["other-filetype"] : params["filetype"] 
  require_relative './lib/frontend-uploader'
  require_relative './lib/facebook_archiver'
  require_relative './lib/twitter_archiver'
  require_relative './lib/instagram_archiver'

  begin
    f = Stevedore::FacebookArchiver.new(es_host, params["index-name"], frontend_s3_bucket)
    f.facebook_access_key = params["facebook-access-key"]
    f.screen_names = facebook_handles
    f.scrape_and_upload! settings.logs
    f = Stevedore::TwitterArchiver.new(es_host, params["index-name"], frontend_s3_bucket)
    f.twitter_consumer_key = params["twitter-consumer-key"]
    f.twitter_consumer_secret = params["twitter-consumer-secret"]
    f.twitter_access_token = params["twitter-access-token"]
    f.twitter_access_token_secret = params["twitter-access-token-secret"]

    f.screen_names = twitter_handles
    f.scrape_and_upload! settings.logs
    f = Stevedore::InstagramArchiver.new(es_host, params["index-name"], frontend_s3_bucket)
    f.screen_names = instagram_handles
    f.scrape_and_upload! settings.logs
  rescue StandardError => e
    halt JSON.dump({success: false, error: e.message + "\n" + e.backtrace.join("\n") })
  end


  if f.errors.size > 0  
    settings.logs.puts "#{f.errors.size} failed documents:"
    settings.logs.puts f.errors.inspect 
  end

  # TODO needs work
  settings.logs.puts "Finished uploading documents at #{Time.now}"

  if (!no_front_end) || !frontend_and_media_location.nil?
    frontend_uploader = Stevedore::FrontendUploader.new(es_host, es_index, frontend_s3_bucket, FRONTEND_S3_PATH)
    settings.logs.puts "Uploading front end"
    frontend_uploader.upload_front_end({
            "index_name" => es_index,
            "name" => params["index-title"].to_s,
            "private?" => "FALSE",
            "data_type" => filetype.empty? ? "blob" : filetype,
            "description" => params["index-description"].to_s
    }) unless OPTIONS.no_front_end
    puts "Finished uploading frontend at #{Time.now}"
    frontend_s3_basepath = "https://#{frontend_s3_bucket}.s3.amazonaws.com/#{FRONTEND_S3_PATH}"
    puts "Uploaded to #{es_index}; go check out the search engine at: \n #{File.join(frontend_s3_basepath.gsub("https:", 'http:'), "/stevedore/search.html##{es_index}")}\n "
  end

  settings.logs.puts "Created Stevedore for #{es_index}; go check out https://stevedore.newsdev.net/search/#{es_index} or http://stevedore.adm.prd.newsdev.nytimes.com/search/#{es_index}"  

  if params["local"] != "local"
    frontend_url = File.join(FRONTEND_S3_BASEPATH.gsub("https:", 'http:'), "/stevedore/search.html?first&template=#{filetype.empty? ? "blob" : filetype}##{es_index}")
    settings.logs.puts "Uploaded to #{es_index}; go check out the search engine at: \n #{frontend_url}\n "
  else
    frontend_url = "/search.html?first&template=#{filetype.empty? ? "blob" : filetype}##{es_index}"
  end
  settings.logs.flush
  JSON.dump({success: true, frontend_url: frontend_url})
end


# not actually a stream ;-)
# because sinatra/streaming mysteriously breaks
# in Warbler/Jetty. :(
# Remember, these URLs are actually /upload/stream
get '/stream', provides: 'text/event-stream' do
  str = settings.logs.string
  msg = (str[-10000..-1] || str).gsub("\n", "<br />")
  "data: #{msg}\n\n"
end

at_exit{
  $node.stop if $node
}
