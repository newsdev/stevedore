#!/usr/bin/env jruby
# -*- coding: utf-8 -*-

raise Exception, "You've gotta use JRuby" unless RUBY_PLATFORM == 'java'

# Why Java 8? There's some gross, dumb incompatiblity between Java 1.7 and using HTTPS (SSL) to 
# interact with ElasticSearch. I dunno why...
raise Exception, "You've gotta use Java 1.8; you're on #{java.lang.System.getProperties["java.runtime.version"]}" unless java.lang.System.getProperties["java.runtime.version"] =~ /1\.8/

require 'rika'
require 'ostruct'

require 'openssl'
require 'net/https'
require 'elasticsearch'
require 'elasticsearch/transport/transport/http/manticore'
require 'net/https'
require 'json'
require 'digest/sha1'

require "openssl"
require 'manticore'
require 'fileutils'

require 'aws-sdk'

if __FILE__ == $0
  require 'optparse'



  OPTIONS = OpenStruct.new
  op = OptionParser.new("Usage: upload_to_elasticsearch [options] directory") do |opts|
    opts.on("-hSERVER:PORT", "--host=SERVER:PORT",
            "The location of the ElasticSearch server") do |host|
      OPTIONS.host = host
    end

    opts.on("-iNAME", "--index=NAME",
            "A name to use for the ES index (defaults to using the directory name)") do |index|
      OPTIONS.index = index
    end

    opts.on("-sPATH", "--s3path=PATH",
            "The path under the int-data-dumps bucket where these files will be uploaded. (defaults to ES index)"
      ) do |s3path|
      OPTIONS.s3path = s3path
    end

    opts.on("-fPATH", "--front-end=PATH", 
            ""
      ) do |frontend_location|
      OPTIONS.frontend_location
    end

    opts.on("-N", "--no-front-end",
            "Don't upload the search front-end to S3. (You might already have the front-end somewhere else.)"
      ) do
      OPTIONS.no_front_end
    end

    opts.on( '-?', '--help', 'Display this screen' ) do     
      puts opts
      exit
    end
  end

  op.parse!

  #FYI: to delete an index: curl -X DELETE localhost:9200/indexname/
  unless ARGV.length == 1
    puts op
    exit
  end


  # you can provide either a path to files locally or
  # an S3 endpoint as s3://int-data-dumps/YOURINDEXNAME
  FOLDER = ARGV.shift

end
ES_INDEX =  if OPTIONS.index.nil? || OPTIONS.index == ''
              if(FOLDER.downcase.include?('s3://'))
                s3_path_without_bucket = FOLDER.gsub(/s3:\/\//i, '').split("/", 2).last
                s3_path_without_bucket.gsub(/^.+\//, '').gsub(/[^A-Za-z0-9\-_]/, '')
              else
                FOLDER.gsub(/^.+\//, '').gsub(/[^A-Za-z0-9\-_]/, '')
              end
            else
              OPTIONS.index
            end

FILES_S3_BUCKET = FOLDER.downcase.include?('s3://') ? FOLDER.gsub(/s3:\/\//i, '').split("/", 2).first : 'int-data-dumps'
ES_HOST = OPTIONS.host || "http://localhost:9200"
FILES_S3_PATH = OPTIONS.s3path  || OPTIONS.index
FILES_BASEPATH = OPTIONS.is_local ? "TK" : "https://#{FILES_S3_BUCKET}.s3.amazonaws.com/#{FILES_S3_PATH}"
if (!OPTIONS.no_front_end) || !OPTIONS.frontend_location.nil?
  FRONTEND_S3_BUCKET = OPTIONS.frontend_location.gsub(/s3:\/\//i, '').split("/", 2).first
  FRONTEND_S3_PATH = OPTIONS.frontend_location.gsub(/s3:\/\//i, '').split("/", 2).last  
  FRONTEND_S3_BASEPATH = "https://#{FRONTEND_S3_BUCKET}.s3.amazonaws.com/#{FRONTEND_S3_PATH}"
end

raise ArgumentError, "specify a destination" unless FOLDER
raise ArgumentError, "specify the elasticsearch host" unless ES_HOST

###############################
# actual stuff
###############################

module Stevedore
  class ESUploader
    #creates blobs
    attr_reader :errors

    def initialize
      @errors = []
    end

    def setup!
      @client = Elasticsearch::Client.new({
          log: false,
          url: ES_HOST,
          transport_class: Elasticsearch::Transport::Transport::HTTP::Manticore
        },
      )

      self.create_index!
      self.create_mappings!
    end

    def create_index!
      begin
        @client.indices.create(
          index: ES_INDEX, 
          body: {
            settings: {
              analysis: {
                analyzer: {
                  email_analyzer: {
                    type: "custom",
                    tokenizer: "email_tokenizer",
                    filter: ["lowercase"]
                  }
                },
                tokenizer: {
                  email_tokenizer: {
                    type: "pattern",
                    pattern: "([a-zA-Z0-9_\\.+-]+@[a-zA-Z0-9-]+\\.[a-zA-Z0-9-\\.]+)",
                    group: "0"
                  }
                }
              }
            },
          }) 
      # don't complain if the index already exists.
      rescue Elasticsearch::Transport::Transport::Errors::BadRequest => e
        raise e unless e.message && e.message.include?("IndexAlreadyExistsException")
      end
    end

    def create_mappings!
      @client.indices.put_mapping({
        index: ES_INDEX,
        type: :doc,
        body: {
          "_id" => {
            path: "sha1"
          },          
          properties: { # feel free to add more, this is the BARE MINIMUM the UI depends on
            sha1: {type: :string, index: :not_analyzed},
            title: { type: :string, analyzer: :keyword },
            source_url: {type: :string, index: :not_analyzed},
            modifiedDate: { type: :date, format: "dateOptionalTime" },
            _updated_at: { type: :date },
            analyzed: {
              properties: {
                body: {type: :string, index_OPTIONS: :offsets, term_vector: :with_positions_offsets },
                metadata: {
                  properties: {
                    "Message-From" => {
                      type: "string",
                      fields: {
                        email: {
                          type: "string",
                          analyzer: "email_analyzer"
                        },
                        "Message-From" => {
                          type: "string"
                        }
                      }
                    },
                    "Message-To" => {
                      type: "string",
                      fields: {
                        email: {
                          type: "string",
                          analyzer: "email_analyzer"
                        },
                        "Message-To" => {
                          type: "string"
                        }
                      }
                    }                  
                  }
                }
              }
            }
          }
        }
      }) # was "rescue nil" but that obscured meaningful errors
    end

    def frontend_config_details
      es_uri = URI(ES_HOST)
      document_sets_path = "document_sets.json" #TODO
<<-CONFIG
// the details for how to connect to your ElasticSearch instance
// and where to get metadata from 
// get AUTOMATICALLY written here.
// If you edit this file, it will get overwritten and your changes erased if
// you ever reupload the frontend..

Stevedore.config = {
  prdHost: "#{es_uri.host}",
  prdPort: "#{es_uri.port}",
  prdScheme: "#{es_uri.scheme}",
  prdPath: "#{es_uri.path}",
  document_set_meta_json: "#{document_sets_path}"
}

// if a document set has multiple data types in it,
// you can choose one content type to be displayed with your chosen list_view
// and detail_view templates, and the rest displayed as "blobs" (just their text).
// write a string or Regexp here that will be matched against the analyzed.metadata["Content-Type"]
// of each document to determine whether to use the chosen template (if it matches)
// or the blob template (if it doesn't match)
Stevedore.content_types = {
  'email': "message/rfc822",
  'hypothetical': /application\\\/pdf/,
  'daily_worker': /.*/,
}
CONFIG
    end

    def upload_front_end(new_index_details)
      Aws.config.update({
        region: 'us-east-1',
      })
      s3 = Aws::S3::Resource.new
      bucket = s3.bucket(FRONTEND_S3_BUCKET)
      things_to_write = ["app/**/*", "lib/**/*", "templates/**/*", "document_sets.json", "index.html", "search.html", "LICENSE"]
      things_to_write.each do |path|
        Dir.glob(path).each do |filename|
          puts "starting #{filename}"
          next if File.directory?(filename)
          open(filename, 'r') do |f|
            file_contents = f.read
            content_type =  if filename.match(/\.json$/)
                              "application/json"
                            elsif filename.match(/\.template$/)
                              "text/plain"
                            elsif filename.match(/\.js$/)
                              "text/javascript"
                            elsif filename.match(/\.html$/)
                              "text/html"
                            elsif filename.match(/\.svg$/)
                              "image/svg+xml"
                            elsif filename.match(/\.eot$/)
                              "application/vnd.ms-fontobject"
                            elsif filename.match(/\.ttf$/)
                              "application/x-font-ttf"
                            elsif filename.match(/\.woff$/)
                              "application/font-woff"
                            elsif filename.match(/\.css$/)
                              "text/css"
                            else
                              "text/plain"
                            end
            if filename == "app/config.js"
              file_contents = frontend_config_details
            elsif filename == "document_sets.json"
              document_sets = if File.exists?(filename)
                                open(filename, 'r') do |f|
                                  begin
                                    JSON.load(f.read)
                                  rescue JSON::ParserError
                                    {"document sets" => []}
                                  end
                                end
                              else
                                {"document sets" => []}
                              end 
              document_sets["document sets"] ||= []
              new_document_sets = document_sets["document sets"]
              new_document_sets << new_index_details
              document_sets["document sets"] =  new_document_sets
              file_contents = JSON.dump(document_sets)
            elsif filename == "index.html" || filename == "search.html"
              file_contents.gsub("<head>", "<head><base href='#{File.join(FRONTEND_S3_BASEPATH, 'stevedore/')}'")
            end
            puts "writing #{filename} to #{File.join(FRONTEND_S3_PATH, "stevedore", filename)}"
            puts "size: #{file_contents.size}"
            resp = bucket.put_object({
              key: File.join(FRONTEND_S3_PATH, "stevedore", filename),
              body: file_contents,
              content_type: content_type
            })
          end
        end
      end
    end

    def bulk_upload_to_es!(data)
      begin
        resp = @client.bulk body: data.map{|datum| {index: {_index: ES_INDEX, _type: 'doc', data: datum }} }
      rescue JSON::GeneratorError
        data.each do |datum|
          begin
            @client.bulk body: [datum].map{|datum| {index: {_index: ES_INDEX, _type: 'doc', data: datum }} }
          rescue JSON::GeneratorError
            next
          end
        end
        resp = nil
      end
      resp
    end

    def process_document(filename, filename_for_s3)

      begin
        content, metadata = Rika.parse_content_and_metadata(filename)
        case 
        when metadata["Content-Type"] == "message/rfc822"
          ::Stevedore::StevedoreEmail.new_from_tika(content, metadata, filename_for_s3, filename).to_hash
        # all the pieces you need for OCR, as a bonus prize for reading the source
        # you need tesseract >3.04 and imagemagick (for `convert`)
        # when metadata["Content-Type"] == "application/pdf" && (content.match(/\A\s*\z/)
        #   # this is a scanned PDF.
        #   puts "scanned PDF #{File.basename(filename)} detected; OCRing"
        #   pdf_basename = filename.gsub(".pdf", '')
        #   `convert -monochrome -density 300x300 "#{filename}" -depth 8 "#{pdf_basename}.png"`
        #   (Dir["#{pdf_basename}-*.png"] + Dir["#{pdf_basename}.png"]).sort_by{|png| (matchdata = png.match(/-\d+\.png/)).nil? ? 0 : matchdata[0].to_i }.each do |png|
        #     `tesseract "#{png}" "#{png} pdf"`
        #     files = Dir["#{pdf_basename}-*.png.pdf"].sort_by{|pdf| Regexp.new("#{pdf_basename}-([0-9]+).png.pdf").match(pdf)[1].to_i }
        #     `pdftk "#{files.join('" "')}" cat output "#{pdf_basename}.ocr.pdf"`
        #     `rm -f #{png}` rescue nil
        #   end.join("\n\n")
        #   content, _ = Rika.parse_content_and_metadata(filename)
        #   puts "OCRed content (#{File.basename(filename)}) length: #{content.length}"
        #   ::Stevedore::StevedoreBlob.new_from_tika(content, metadata, filename_for_s3, filename).to_hash
        else
          ::Stevedore::StevedoreBlob.new_from_tika(content, metadata, filename_for_s3, filename).to_hash
        end
      rescue StandardError, java.lang.NoClassDefFoundError => e
        STDERR.puts e.inspect
        STDERR.puts "#{e} #{e.message}: #{filename}"
        STDERR.puts e.backtrace.join("\n")
        # puts "\n"
        @errors << filename
        nil
      end
    end

    def do!(output_stream=STDOUT)
      puts "Processing documents from #{FOLDER}"
      #TODO: do from S3 too! That means we can do download_urls really easily
      slice_size = 100
      docs_so_far = 0

      if FOLDER.downcase.include?("s3://")
        Dir.mktmpdir do |dir|
          Aws.config.update({
            region: 'us-east-1',
          })
          s3 = Aws::S3::Resource.new

          bucket = s3.bucket(FILES_S3_BUCKET)
          s3_path_without_bucket = FOLDER.gsub(/s3:\/\//i, '').split("/", 2).last
          puts "prefix: #{s3_path_without_bucket}"
          bucket.objects(:prefix => s3_path_without_bucket).each_slice(slice_size) do |slice_of_objs|
            output_stream.puts "starting a set of #{slice_size}"
            slice_of_objs.map! do |obj|
              next if obj.key[-1] == "/"
              next if obj.key.match( "/stevedore/" ) # don't index the search frontend if it's in the bucket.
              FileUtils.mkdir_p(File.join(dir, File.dirname(obj.key), 'asdf.txt' )) 
              tmp_filename = File.join(dir, obj.key)
              begin
                body = obj.get.body.read
                File.open(tmp_filename, 'wb'){|f| f << body}
              rescue Aws::S3::Errors::NoSuchKey
                @errors << obj.key
              rescue ArgumentError
                File.open(tmp_filename, 'wb'){|f| f << body.nil? ? '' : body.chars.select(&:valid_encoding?).join}
              end

              doc = process_document(tmp_filename, "https://#{FILES_S3_BUCKET}.s3.amazonaws.com/" + obj.key)
              begin             
                FileUtils.rm(tmp_filename)
              rescue Errno::ENOENT
                # try to delete, but no biggie if it doesn't work for some weird reason.
              end
              doc
            end
            begin
              slice_of_objs.compact!
              docs_so_far += slice_of_objs.size
              resp = bulk_upload_to_es!(slice_of_objs) unless slice_of_objs.empty?
              output_stream.puts "uploaded #{slice_of_objs.size} files to #{ES_INDEX}; #{docs_so_far} uploaded so far"
              puts "uploaded #{slice_of_objs.size} files to #{ES_INDEX}; #{docs_so_far} uploaded so far"
            rescue Manticore::Timeout, Manticore::SocketException
              retry
            end
            output_stream.puts "Errors in bulk upload: #{resp.inspect}" if resp && resp["errors"]
          end
        end
      else
        Dir[FOLDER + (FOLDER.include?('*') ? '' : '/**/*')].each_slice(slice_size) do |slice_of_files|
          output_stream.puts "starting a set of #{slice_size}"
          slice_of_files.map! do |filename|
            next unless File.file?(filename)
            filename_for_s3 = filename.gsub(FOLDER, '') # TODO: needs s3-ification

            process_document(filename,  FILES_BASEPATH + filename_for_s3)
          end
          begin
              slice_of_files.compact!
              resp = bulk_upload_to_es!(slice_of_files)
              docs_so_far += slice_of_files.size
              output_stream.puts "uploaded #{slice_of_files.size} files to #{ES_INDEX}; #{docs_so_far} uploaded so far"
              puts "uploaded #{slice_of_files.size} files to #{ES_INDEX}; #{docs_so_far} uploaded so far"
          rescue Manticore::Timeout, Manticore::SocketException
            retry
          end
          puts "Errors in bulk upload: #{resp.inspect}" if resp && resp["errors"]
        end
      end
    end
  end

  class StevedoreBlob
    attr_accessor :title, :text, :download_url, :extra
    def initialize(title, text, download_url=nil, extra={})
      self.title = title || download_url
      self.text = text
      self.download_url = download_url
      self.extra = extra
      raise ArgumentError, "StevedoreBlob extra support not yet implemented" if extra.keys.size > 0
    end

    def clean_text
      @clean_text ||= text.gsub(/<\/?[^>]+>/, '') # removes all tags
    end 

    def self.new_from_tika(content, metadata, download_url, filename)
      self.new(metadata["title"], content, download_url)
    end

    def to_hash
      {
        "sha1" => Digest::SHA1.hexdigest(download_url),        
        "title" => title.to_s,
        "source_url" => download_url.to_s,
        "file" => {
          "title" => title.to_s,
          "file" => clean_text.to_s
        },
        "analyzed" => {
          "body" => clean_text.to_s,
          "metadata" => {
            "Content-Type" => extra["Content-Type"] || "text/plain"
          }
        },
        "_updatedAt" => Time.now      
      }
    end

    # N.B. the elasticsearch gem converts your hashes to JSON for you. You don't have to use this at all.
    # def to_json
    #   JSON.dump to_hash
    # end
  end
end

require 'cgi'
require 'digest/sha1'
module Stevedore
  class StevedoreEmail < StevedoreBlob


    # TODO write wrt other fields. where do those go???
    attr_accessor :creation_date, :message_to, :message_from, :message_cc, :subject, :attachments, :content_type

    def self.new_from_tika(content, metadata, download_url, filepath)
      t = super
      t.creation_date = metadata["Creation-Date"]
      t.message_to = metadata["Message-To"]
      t.message_from = metadata["Message-From"]
      t.message_cc = metadata["Message-Cc"]
      t.subject = metadata["subject"]
      t.attachments = metadata["X-Attachments"].to_s.split("|").map do |raw_attachment_filename| 
        attachment_filename = CGI::unescape(raw_attachment_filename)
        possible_filename = File.join(File.dirname(filepath), attachment_filename)
        eml_filename = File.join(File.dirname(filepath), File.basename(filepath, '.eml') + '-' + attachment_filename)
        s3_path = S3_BASEPATH + File.dirname(filepath).gsub(::FOLDER, '')

        if File.exists? possible_filename
          s3_path + '/' + CGI::escape(File.basename(possible_filename))
        elsif File.exists? eml_filename
          s3_path + '/' + CGI::escape(File.basename(eml_filename))
        else
          STDERR.puts "Tika X-Attachments: " + metadata["X-Attachments"].to_s.inspect
          STDERR.puts "Couldn't find attachment '#{attachment_filename}' aka '#{File.basename(filepath, '.eml') + '-' + attachment_filename}' from '#{raw_attachment_filename}' from #{download_url}"
          nil
        end
      end.compact
      t
    end


    def to_hash
      {
        "sha1" => Digest::SHA1.hexdigest(download_url),
        "title" => title.to_s,
        "source_url" => download_url.to_s,
        "file" => {
          "title" => title.to_s,
          "file" => text.to_s
        },
        "analyzed" => {
          "body" => text.to_s,
          "metadata" => {
            "Content-Type" => content_type || "message/rfc822",
            "Creation-Date" => creation_date,
            "Message-To" => message_from.is_a?(Enumerable) ? message_from : [ message_from ],
            "Message-From" => message_to.is_a?(Enumerable) ? message_to : [ message_to ],
            "Message-Cc" => message_cc.is_a?(Enumerable) ? message_cc : [ message_cc ],
            "subject" => subject,
            "attachments" => attachments
          }
        },
        "_updatedAt" => Time.now
      }
    end

  end
end


if __FILE__ == $0
  f = Stevedore::ESUploader.new()
  f.setup!
  f.do!(STDOUT)

  if f.errors.size > 0  
    STDERR.puts "#{f.errors.size} failed documents:"
    STDERR.puts f.errors.inspect 
  end

  puts "Uploading front end"
  f.upload_front_end unless OPTIONS.no_front_end
  puts "Finished at #{Time.now}"
  puts "Uploaded to #{ES_INDEX}; go check out the search engine at: \n #{File.join(FRONTEND_S3_BASEPATH.gsub("https:", 'http:'), "/stevedore/search.html##{ES_INDEX}")}\n "
end
