require_relative './uploader/gui_for_uploader.rb'
require 'rika'
require 'fileutils'
# if you're testing locally and intend to run Stevedore via Nginx (or Apache, I suppose)
# set the NGINXSTYLE environment variable to simulate the URLs accepted there.

$search_files = nil # just initializing outside of any closures.

def data_dir
  # OS X: ~/Library/Application Support/Stevedore
  # Win:  %APPDATA%/Stevedore
  # Linux: ~/.stevedore


  # when invoking as "java -Dstevedore.data_dir=/foo/bar ... -jar stevedore.war"
  data_dir = java.lang.System.getProperty('stevedore.data_dir')
  unless data_dir.nil?
    return java.io.File.new(data_dir).getPath
  end

  # when invoking with env var
  data_dir = ENV['TABULA_DATA_DIR']
  unless data_dir.nil?
    return java.io.File.new(data_dir).getPath
  end

  # use the usual directory in (system-dependent) user home dir
  data_dir = nil
  case java.lang.System.getProperty('os.name')
  when /Windows/
    # APPDATA is in a different place (under user.home) depending on
    # Windows OS version. so use that env var directly, basically
    appdata = ENV['APPDATA']
    if appdata.nil?
      home = java.lang.System.getProperty('user.home')
    end
    data_dir = java.io.File.new(appdata, '/Stevedore').getPath

  when /Mac/
    home = java.lang.System.getProperty('user.home')
    data_dir = File.join(home, '/Library/Application Support/Stevedore')


  else
    # probably *NIX
    home = java.lang.System.getenv('XDG_DATA_HOME')
    if !home.nil?
      # XDG
      data_dir = File.join(data_home, '/stevedore')
    else
      # other, normal *NIX systems
      home = java.lang.System.getProperty('user.home')
      home = '.' if home.nil?
      data_dir = File.join(home, '/.stevedore')
    end
  end # /case

  data_dir
end

def ensure_templates_exist!
  Dir.glob("templates/**/*").each do |path|
    new_path = File.join(data_dir, path.gsub(File.dirname(__FILE__), ''))
    next if File.exists?(new_path) # don't clobber existing, potentially-edited files
    next unless File.basename(path).include?(".") # skip folders, i.e. anything in templates with no file extension (we can't File.file? or Dir.dir? because these might be in a JAR)
    if "#{$PROGRAM_NAME}".include?("stevedore.war") || "#{$PROGRAM_NAME}".include?("stevedore.jar")
      stream = self.to_java.get_class.get_class_loader.get_resource_as_stream('/' + path)
    else
      stream = open( File.join(File.dirname(__FILE__), path) ){|f| f.read}
    end
    FileUtils.mkdir_p(File.dirname(new_path))
    open(new_path, 'w'){|f| f << stream }

    # FileUtils.cp(path, new_path) if !File.exists?(new_path)
  end
end


def start_local_elasticsearch_server
  Dir[File.join(File.dirname(__FILE__), "elasticsearch-1.7.2/lib/*.jar")].each do |jar|
    require jar
  end
  # https://github.com/Asquera/elasticsearch-node/blob/master/lib/elasticsearch-node/embedded.rb
  node_builder = org.elasticsearch.node.NodeBuilder.nodeBuilder.loadConfigSettings(true)
  settings_builder = org.elasticsearch.common.settings.ImmutableSettings.settingsBuilder

  settings_builder.put("path.conf", File.join(File.dirname(__FILE__), "config"))
  settings_builder.put("http.cors.enabled", true)

  settings_builder.put("path.data", data_dir)
  settings_builder.put("path.logs", data_dir)

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
    # puts "RFP: #{requested_file_path} " 
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

if ENV["NGINXSTYLE"]
  puts "dev server"
  require './dev_server'
  use Rack::Static,
  :urls => ["/document_sets.json"],
  :root => File.dirname(__FILE__),
  :index => 'index.html',
  :header_rules => [[:all, {'Cache-Control' => 'public, max-age=3600'}]]  
  use Rack::Static, :urls => ["/app"]
  use Rack::Static, :urls => ["/lib"]
  use Rack::Static, :urls => ["/templates"]
  run Rack::URLMap.new('/upload' => Sinatra::Application, '/search' => Stevedore::NginxSimulator)
else
  use Rack::Static,
  :urls => ["/search.html", "/index.html", "/document_sets.json"],
  :root => File.dirname(__FILE__),
  :index => 'index.html',
  :header_rules => [[:all, {'Cache-Control' => 'public, max-age=3600'}]]

  use Rack::Static, :urls => ["/app"]
  use Rack::Static, :urls => ["/lib"]
  use Rack::Static, :urls => ["/templates"]
  run Rack::URLMap.new('/upload' => Sinatra::Application)
end

ensure_templates_exist!
# start_local_elasticsearch_server

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


  puts "template files are located in #{data_dir}/templates. edit 'em if you want."
end



