_.extend(Stevedore, Backbone.Events);
_.templateSettings = {             // mustache-style templating
  interpolate: /\{\{=(.+?)\}\}/g,  // oh god I hate computers
  evaluate:    /\{\{(.+?)\}\}/g    // really and truly
    
                                   // do you know anyone
                                   // who's looking to hire an
                                   // apprentice shepherd?
};


// primarily for testing and for the "local"-only demo version
// you can set ?template=email or ?template=whatever to set the default template type
function getParameterByName(name) {
    name = name.replace(/[\[]/, "\\[").replace(/[\]]/, "\\]");
    var regex = new RegExp("[\\?&]" + name + "=([^&#]*)"),
        results = regex.exec(location.search);
    return results === null ? null : decodeURIComponent(results[1].replace(/\+/g, " "));
}
Stevedore.template_name_from_querystring = getParameterByName("template")

// maybe this should be a function called on each ES hit
// and returns whether to use blob or the project-specific template?
// e.g. function(hit){ return hit.analyzed.metadata["Content-Type"] == "message/rfc822"}
Stevedore.default_template_names = {
        list_view: Stevedore.template_name_from_querystring !== null ? Stevedore.template_name_from_querystring : 'blob',
        detail_view: Stevedore.template_name_from_querystring !== null ? Stevedore.template_name_from_querystring : 'blob',
        search_form: Stevedore.template_name_from_querystring !== null ? Stevedore.template_name_from_querystring : 'blob',
        query_builder: Stevedore.template_name_from_querystring !== null ? Stevedore.template_name_from_querystring : 'blob',
        css: Stevedore.template_name_from_querystring !== null ? Stevedore.template_name_from_querystring : 'blob'
}
Stevedore.Views = {};
Stevedore.Models = {};
Stevedore.Collections = {};
Stevedore.projects = {}

Stevedore.env = "prd"; // You may want to change this and add additional options -- maybe a 'dev' environment or a 'sensitive' one to the
                 // Stevedore.config hash. You may want to distinguish between them by the URL, e.g.
                 // Stevedore.env = window.location.host.indexOf("localhost") > -1 ? 'dev' : 'prd';
                 // Stevedore.config is set in app/config.js

Stevedore.project = Stevedore.config.use_slash_based_routing ? window.location.pathname.split("/")[2] : window.location.hash.split("/")[0].replace("#", ''); // the first item; [0] is an empty string, [1] is 'search'
Stevedore.es_host = Stevedore.config[Stevedore.env + 'Host']
Stevedore.es_port = Stevedore.config[Stevedore.env + 'Port'] || 9200;
Stevedore.es_scheme = Stevedore.config[Stevedore.env + 'Scheme'] || 'http';
Stevedore.es_path = Stevedore.config[Stevedore.env + 'Path'] || '';
Stevedore.es_index = Stevedore.project;
//var es_doctype = 'doc'
Stevedore.max_hits = 50;

$('.page-header #project-name').attr('href', (Stevedore.config.use_slash_based_routing ? '/search/' : '/search.html#') + Stevedore.project);
$('.page-header #project-name span').text(Stevedore.project); // placeholder until config comes back, or if the index isn't defined in the config.
$('.navbar .navbar-header .navbar-brand').attr('href', Stevedore.config.use_slash_based_routing ? '/search' : 'index.html');
// Default Object
// each ES object, by convention, is required to define these fields
// all objects are merged onto this, so the fields are always defined
Stevedore.def_obj = {
  id: '1',
  file: {file: 'Error (4326): No text found.' }, // lol that's an SRID, not an error code!!
  analyzed: {},
  source_url: 'http://www.nytimes.com',

  options: { // for the view
    show_whole_body: true // this could potentially come from the UI.
  }
}
if(typeof HumanHasher !== 'undefined'){
  Stevedore.HumanHasher = new HumanHasher();
}
Stevedore.templates = {};

Stevedore.getTemplates = function(project, cb){
  Stevedore.template_names = _.extend({}, Stevedore.default_template_names, Stevedore.projects[project]);
  console.log('project', project, ' => ', Stevedore.template_names);
  $("head").append($("<link rel='stylesheet' href='"+(Stevedore.config.use_slash_based_routing ? '/search/' : '')+"templates/css/"+Stevedore.template_names['css']+".css?_cachebuster=201604071122' type='text/css' media='screen' />"));

  var q = queue()

  q.defer(function(){
    $.ajax({
      url: (Stevedore.config.use_slash_based_routing ? '/search/' : '') + "templates/query_builder/" + Stevedore.template_names['query_builder'] + ".js?_cachebuster=201604071122",
      dataType: "script",
      async: true,
      success: function(data, status, jqxhr){
        Stevedore.Models.Search = Stevedore.Models.DefaultSearch.extend(Stevedore.QueryBuilder); // create the methods we want!
        Stevedore.saved_searches_collection = new Stevedore.Collections.SavedSearches([], {model: Stevedore.Models.Search})
        Stevedore.saved_searches_view = new Stevedore.Views.SavedSearches({ el: $('#saved-searches-container')[0] } );
        Stevedore.saved_searches_collection.fetch();
        Stevedore.trigger('stevedore:querybuilder-loaded');

        if(cb) cb(); // only if we're inside q...
      },
      error: function(a,b,c){
        console.log('error getting query-builder : ', a,b,c);
        if(cb) cb(); // only if we're inside q...
      }
    });
  });
  _(['search_form', 'list_view', 'detail_view']).each(function(folder){
    _(Stevedore.template_names[folder] == "blob" ? [Stevedore.template_names[folder]] : [Stevedore.template_names[folder], "blob"]).each(function(template_type){
      Stevedore.templates[template_type] = {}; // template_type is one of "blob" or "email" or others
      q.defer(function(cb){
        $.ajax({
          url: (Stevedore.config.use_slash_based_routing ? '/search/' : '') + "templates/" + folder + "/" + template_type + ".template?_cachebuster=201604071122",
          dataType: "text",
          async: true,
          success: function(data, status, jqxhr){
            Stevedore.templates[template_type] = Stevedore.templates[template_type] || {}
            Stevedore.templates[template_type][folder] = _.template(data);
            if (Stevedore.search_view) Stevedore.search_view.render(); // problem if this happens before Stevedore.search_form is craeted
            if (Stevedore.detail_view) Stevedore.detail_view.render();
            if (Stevedore.results_view) Stevedore.results_view.render();
            cb()
          },
          error: function(a,b,c){
            console.log('error getting template('+folder+', '+template_type+') : ', a,b,c);
            cb();
          }
        });
      });
    });
  });
  q.awaitAll(function(){ if(cb) cb(); })
}
if(typeof elasticsearch !== 'undefined'){
  Stevedore.client = new elasticsearch.Client({
    // host: es_target,
    host:{
      protocol: Stevedore.es_scheme,
      host: Stevedore.es_host,
      path: Stevedore.es_path,
      port: Stevedore.es_port,
    }
  });
}

Stevedore.get_mapping = function(){
  // https://stevedore.newsdev.net/es/jeb-bush-emails/_mapping
    Stevedore.client.indices.getMapping({index: Stevedore.es_index})
      .then(
        _.bind(function(resp){
          var index_name = _.has(resp, Stevedore.es_index) ? Stevedore.es_index : _.keys(resp)[0]; // Stevedore.es_index might be an alias.
          var es_type = _.has(resp[index_name].mappings, 'doc') ? 'doc' : _.keys(resp[index_name].mappings)[0];
          Stevedore.mapping = typeof resp[index_name] !== 'undefined' ? resp[index_name].mappings[es_type] : null;
          try{
            Stevedore.config.highlighting_enabled = typeof resp[index_name] !== 'undefined' ? resp[index_name].mappings[es_type].properties.analyzed.properties.body.index_options === "offsets" : false;
          }catch(TypeError){
            Stevedore.config.highlighting_enabled = false;
          }
       }, this),
        function(error){ 
          console.log("Mapping couldn't be fetched", error);          
          window.location = "index.html?error=mapping";
        });

}
Stevedore.get_count = function(){
  Stevedore.client.count({ index: Stevedore.es_index})
    .then(
      _.bind(function(resp){
      Stevedore.blob_count = resp.count;
     }, this), 
      function(error){ 
        console.log("Count couldn't be fetched", error);        
        window.location = "index.html?error=count";
      });
}


// Gets the list of indexes ("/_aliases") and the metadata for each index and,
// once we've got both of them, then sets the metadata on the Stevedore object
Stevedore.get_config = function(cb){
  function _parsing_callback(){
    // this will get called twice, once where one of these items is undefined.
    // we only want it to run once, when they're both defined.
    if(typeof Stevedore.document_set_metadata !== 'undefined' && typeof Stevedore.document_sets !== 'undefined'  ){
      if(cb) cb();
    }
  }
  $.getJSON((Stevedore.es_port == 443 ? 'https://' :  'http://') + Stevedore.es_host + ':' + Stevedore.es_port + Stevedore.es_path + '/_aliases', {}, function(data){
    var keys = _(data).keys();
    Stevedore.document_sets = [];
    // if an index has aliases, we display the alias (or aliases) not the "official" index name
    // cf. https://www.elastic.co/blog/changing-mapping-with-zero-downtime
    _(keys).each(function(key){
     if(_.isEmpty(data[key]["aliases"])){
       Stevedore.document_sets.push(key);
     }else{
       _(data[key]["aliases"]).each(function(obj, alias){
         Stevedore.document_sets.push(alias);
       })
     }
    })
    _parsing_callback();
  })
  $.get(Stevedore.config.document_set_meta_json || '/document_sets.json', {}, function(data){
    Stevedore.document_set_metadata = {};
    _(data["document sets"]).each(function(document_set){
      if( _.isNull(document_set.name)) document_set.name = document_set.index_name;
      document_set.samplesearches = _(data["sample searches"]).chain().filter(function(search){ return search.index_name == document_set.index_name }).map(function(search){ search['name'] = search['description']; return search}).value()
      Stevedore.document_set_metadata[document_set.index_name] = document_set;
      Stevedore.document_set_metadata[document_set.index_name]["desc"] = Stevedore.document_set_metadata[document_set.index_name].description;
      Stevedore.projects[document_set.index_name] = {
        list_view: document_set.data_type,
        detail_view: document_set.data_type,
        search_form: document_set.data_type,
        query_builder: document_set.data_type,
        css: document_set.data_type
      }
    })
    _parsing_callback();
  })
}

// if this is a search page (not the docdeck)
if(Stevedore.es_index) Stevedore.get_count();
if(Stevedore.es_index) Stevedore.get_mapping();
if(Stevedore.es_index) Stevedore.get_config(function(){
  Stevedore.getTemplates(Stevedore.project, function(){
    if (Stevedore.search_view ) Stevedore.search_view.render();
  })
  var project_metadata = Stevedore.document_set_metadata[Stevedore.project];
  if(project_metadata) $('.page-header #project-name span').text(project_metadata.name);
  if(project_metadata) $('.page-header #project-desc').text(project_metadata.desc);

});

Stevedore.es_hit_to_blob = function(hit){
  var blob = hit._source;
  blob.id = hit._id;
  if(blob.id.match(/[0-9a-f]{32}/)){
    blob.human_id = Stevedore.HumanHasher.humanize(blob.id, words = 4)
  }else{
    blob.human_id = blob.id;
  }

  // // in case the postprocess script hasn't been run yet.
  // // This is a bad idea to enable. Just use it for testing :) - J
  // It's a bad idea because items (like dates) aren't in the right place in the index.
  // So you can't search them EVEN THOUGH IT LOOKS LIKE YOU SHOULD BE ABLE TO
  // We may be able to do more of the postprocess work by changing the mappings
  // e.g. moving the date field queries to point to _source.file.metadata.Creation-Date
  // and using postprocess only to do attachment tika stuff, rather than moving keys around.
  // if(blob.file.metadata && typeof blob.analyzed === 'undefined'){
  //   blob.analyzed = {};
  //   blob.analyzed.metadata = blob.file.metadata;
  //   blob.analyzed.body = blob.file.file;
  // }

  blob.highlighted = {};

  var highlight_field = hit.highlight && hit.highlight["analyzed.body.snowball"] ? "analyzed.body.snowball" : "analyzed.body";

  // TODO: refactor the text-to-HTML stuff so it's not repeated so much
  // /<(?!span)/g works better anyways as a RHS

  if(hit.highlight && hit.highlight[highlight_field]){
    blob.highlighted.snippets = (hit.highlight[highlight_field].join("\n\n") == blob[highlight_field] ? '' : '... ') + hit.highlight[highlight_field].   
                                          join("\n\n").
                                          replace(/<\/?[^>]+>/g, '').
                                          replace(/\n\n+/g, "</p><p class='body'>").
                                          replace(/\[HIGHLIGHT\]/g, '<span class="highlight">'). 
                                          replace(/\[\/HIGHLIGHT\]/g, '</span>') + (hit.highlight[highlight_field].join("\n\n") == blob[highlight_field] ? '' : ' ...')
    // if there are more than 3 linebreaks above, strip all but two, so highlighted thing is always in place
    var split_highlighted_snippets = blob.highlighted.snippets.split('<span class="highlight">')[0].split("</p>");
    if( split_highlighted_snippets.length > 3){
      blob.highlighted.snippets = blob.highlighted.snippets.split("</p>").slice(split_highlighted_snippets.length - 2).join("</p>");
    }
  }

  // 2015-11-10: decided to change this from \n\n+ to \n\n* for replacing newlines in source text with <p> tags
  // not sure why I ever required 2 or more.
  // 2015-11-16: decided to change it back because it split too many lines in for jeb-george-documents (search "chair")
  // For snippets only, I'm going to only make \n\n+ a new paragraph, but use line breaks as is (that is, turn \n\n* into <p>) for the body.
  // Maybe a solution would be to see if there are any paragraph breaks and, if there are, 
  if(blob.analyzed && blob[highlight_field]){
    blob[highlight_field] = blob[highlight_field].
                                  replace(/<\/?[^>]+>/g, '').
                                  replace(/\n\n*/g, "</p><p class='body'>");
  }
  if(blob.analyzed && blob.analyzed.body){
    blob.analyzed.body = blob.analyzed.body.
                                  replace(/<\/?[^>]+>/g, '').
                                  replace(/\n\n*/g, "</p><p class='body'>");
  }  
  if(blob.file && blob.file.file){
    blob.file.file = blob.file.file.
                                  replace(/<\/?[^>]+>/g, '').
                                  replace(/\n\n*/g, "</p><p class='body'>");
  }
  blob.attachments = []
  processAttachment = function(attachment) {
      blob.attachments.push(attachment);
  }
  // I assume there's a better way to do this, but this seems to work ...
  if(blob.analyzed && blob.analyzed.metadata && blob.analyzed.metadata.attachments && blob.analyzed.metadata.attachments.length > 0){
    _.each(blob.analyzed.metadata.attachments, processAttachment);
  } 
  if(blob.s3_path){
    processAttachment(blob.s3_path);
  } 
  if(blob.screenshot_urls){
    _.each(blob.screenshot_urls, processAttachment);
  } 

  // console.log(hit.highlight);

  return _.extend({}, Stevedore.def_obj, // ensure required fields are present.
                      blob
                 );
}


