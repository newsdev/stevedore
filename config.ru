require_relative './uploader/upload_gui.rb'
require 'rika'

use Rack::Static,
  :urls => ["/search.html", "/index.html", "/document_sets.json"],
  :root => File.dirname(__FILE__),
  :index => 'index.html',
  :header_rules => [[:all, {'Cache-Control' => 'public, max-age=3600'}]]

use Rack::Static, :urls => ["/app"]
use Rack::Static, :urls => ["/lib"]
use Rack::Static, :urls => ["/templates"]

$search_files = nil

def start_local_elasticsearch_server
  Dir[File.join(File.dirname(__FILE__), "elasticsearch-1.7.2/lib/*.jar")].each do |jar|
    require jar
  end
  # https://github.com/Asquera/elasticsearch-node/blob/master/lib/elasticsearch-node/embedded.rb
  node_builder = org.elasticsearch.node.NodeBuilder.nodeBuilder.loadConfigSettings(true)
  settings_builder = org.elasticsearch.common.settings.ImmutableSettings.settingsBuilder

  settings_builder.put("path.conf", File.join(File.dirname(__FILE__), "config"))
  settings_builder.put("http.cors.enabled", true)

  tuple = org.elasticsearch.node.internal.InternalSettingsPreparer.prepareSettings(settings_builder.build, true)
  org.elasticsearch.common.logging.log4j.LogConfigurator.configure(tuple.v1());
  $node = node_builder.settings(settings_builder).node  #   // on startup

  http_server =  $node.injector.getInstance(org.elasticsearch.http.HttpServer.java_class)
  socket_address = http_server.info.address.publishAddress.address
  connection_string = "#{socket_address.host_string}:#{socket_address.port}"
  connection_string
end



# a ridiculously hacky way to -- if the user has a 'local' server
# once they've set a folder to index
# serve files from there.
map "/files/" do
  run Proc.new{ |env|
    next ['404', {'Content-Type' => 'text/html'}, ['File not found (1).'] ] if $search_files.nil? 

    # based on
    # https://practicingruby.com/articles/implementing-an-http-file-server
    path         = URI.unescape(env["PATH_INFO"])
    clean = []
    # Split the path into components
    parts = path.split("/")
    parts.each do |part|
      # skip any empty or current directory (".") path components
      next if part.empty? || part == '.'
      # If the path component goes up one directory level (".."),
      # remove the last clean component.
      # Otherwise, add the component to the Array of clean components
      part == '..' ? clean.pop : clean << part
    end

    requested_file_path = File.join($search_files, *clean)
    puts "RFP: #{requested_file_path} " 
    next ['404', {'Content-Type' => 'text/html'}, ['File not found (2).'] ] unless File.file?(requested_file_path)
    Rack::File.new(requested_file_path).call(env.merge({"PATH_INFO" => ''}))
  }
end

map "/quit" do
  run Proc.new{ |env|
    Sinatra::Application.quit! # cleanly exits Sinatra, but doesn't quit rack.
    next ['200', {'Content-Type'=> 'text/html'}, ['<html><head><title>Thanks for using Stevedore</title></head><body>Bye! Feel free to close this tab. The Stevedore program has now been quit.<script>var xhr = new XMLHttpRequest(); xhr.open("GET", "/reallyquit"); xhr.send();</script></body></html>']]
  }
end

map "/reallyquit" do 
  run Proc.new{ |env|
    require 'java'
    exit!
    java.lang.System.exit(0)
  }
end

# map "/wait" do
#   run Proc.new{ |env|
#     Sinatra::Application.quit! # cleanly exits Sinatra, but doesn't quit rack.
#     next ['200', {'Content-Type'=> 'text/html'}, ['<html><head><title>Wait a minute...</title></head><body>Hi! The Stevedore program is still starting up. This page will refresh until the program is fully booted up.<script>var xhr = new XMLHttpRequest(); xhr.open("GET", "/upload"); xhr.onreadystatechange = function() { if (xhr.readyState == 4) { if(xhr.status){ window.location.href = "/upload" }else{ window.location.reload()} } }; xhr.send(); </script></body></html>']]
#   }
# end


run Rack::URLMap.new('/upload' => Sinatra::Application)
start_local_elasticsearch_server

# this is stolen directly -- shamelessly -- from https://github.com/tabulapdf/tabula/blob/master/config.ru
# only do this if running as jar or app. (if "rackup", we don't
# actually use 8080 by default.)
if "#{$PROGRAM_NAME}".include?("stevedore.war") || "#{$PROGRAM_NAME}".include?("stevedore.jar")

  # don't do "java_import java.net.URI" -- it conflicts with Ruby URI and
  # makes Cuba/Rack really really upset. just call "java.*" classes
  # directly.
  port = java.lang.Integer.getInteger('warbler.port', 8080)
  url = "http://127.0.0.1:#{port}/upload"

  puts "============================================================"
  puts url
  puts "============================================================"

  # Open browser after slight delay. (The server may take a while to actually
  # serve HTTP, so we are trying to avoid a "Could Not Connect To Server".)
  uri = java.net.URI.new(url)
  sleep 1

  have_desktop = false
  if java.awt.Desktop.isDesktopSupported
    begin
      desktop = java.awt.Desktop.getDesktop()
    rescue
      desktop = nil
    else
      have_desktop = true
    end
  end

  # if running as a jar or app, automatically open the user's web browser if
  # the system supports it.
  if have_desktop
    puts "\n======================================================"
    puts "Launching web browser to #{url}\n\n"
    puts "If it does not open in 10 seconds, you may manually open"
    puts "a web browser to the above URL."
    puts "When you're done using the Stevedore interface, you may"
    puts "return to this window and press \"Control-C\" to close it."
    puts "======================================================\n\n"
    desktop.browse(uri)
  else
    puts "\n======================================================"
    puts "Server now listening at: #{url}\n\n"
    puts "You may now open a web browser to the above URL."
    puts "When you're done using the Stevedore interface, you may"
    puts "return to this window and press \"Control-C\" to close it."
    puts "======================================================\n\n"
  end
end



