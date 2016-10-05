/* used in CSV generator */
JSON.flatten = function(data) {
    var result = {};
    function recurse (cur, prop) {
        if (Object(cur) !== cur) {
            result[prop] = cur;
        } else if (Array.isArray(cur)) {
             for(var i=0, l=cur.length; i<l; i++)
                 recurse(cur[i], prop + "[" + i + "]");
            if (l == 0)
                result[prop] = [];
        } else {
            var isEmpty = true;
            for (var p in cur) {
                isEmpty = false;
                recurse(cur[p], prop ? prop+"."+p : p);
            }
            if (isEmpty && prop)
                result[prop] = {};
        }
    }
    recurse(data, "");
    return result;
}

Stevedore.Models.DefaultSearch = Backbone.Model.extend({

  // there are two ways to actually create a Search instance
  // the likeActuallyCreate method in QueryBuilder
  // and the fromString method.
  // for both create an empty instance, then call the relevant method (likeActuallyCreate, fromString)
  // because I don't want to fool around with making new constructors and am not the world's best at JavaScript, etc.

  initialize: function(stuff){
    _.bindAll(this, 'search', 'toQuery');
    this.set({'searched_at': new Date()});
    this.set('pageNum', 0);
    this.set('from', '');
    this.set('to', '');
    this.set('subject', '');
    this.set(stuff);
  },

  search: function(cb){
    this.trigger("stevedore:search-start");
    $('#paginate').hide();
    $('#loading').addClass('loading');
    if (Stevedore.document_collection.size() > 0 ){
      $('#loading').addClass('loading-more');
    }
    console.log('search!', this.attributes);


    Stevedore.client.search({
      index: Stevedore.es_index,
      body: {
        size: Stevedore.max_hits,
        from: this.get('pageNum') * Stevedore.max_hits,
        query: this.toQuery(),
        sort: this.toSort(),
        highlight: {
          fields: {

            "analyzed.body": {
              fragment_size: 300,
              type: Stevedore.config.highlighting_enabled ? 'postings' : null,
              number_of_fragments: 5,
              no_match_size: 300,
              force_source: true,
              pre_tags : ["[HIGHLIGHT]"], // these get converted to HTML in app.js
              post_tags : ["[/HIGHLIGHT]"],              
             },
             "analyzed.body.snowball": {
               fragment_size: 300,
               type: Stevedore.config.highlighting_enabled ? 'postings' : null,
               number_of_fragments: 5,
               no_match_size: 300,
               force_source: true,
               pre_tags : ["[HIGHLIGHT]"], // these get converted to HTML in app.js
               post_tags : ["[/HIGHLIGHT]"],              
             }
          }
        }
      }
    }).then(_.bind(function (resp) {
      if(!resp){
        return;
      }

      var raw_hits = resp.hits.hits;
      this.set('hit_count', resp.hits.total);

      var blobs;
      // preprocess blobs
      blobs = _(_.first(raw_hits, Stevedore.max_hits)).map(Stevedore.es_hit_to_blob);

      Stevedore.document_collection.add(blobs);
      this.trigger('stevedore:search-done');
      $('#paginate').show();
      $('#loading').removeClass('loading');
      $('#loading').removeClass('loading-more');
      if(cb) cb();      
    }, this), function (err) {
      //TODO: error messages
    });
  },
  toString: function(){
    var z =encodeURIComponent(_(this.fieldOrder()).map(_.bind(function(field){
      return typeof this.get(field) === 'undefined' ? '' : this.get(field);
    }, this)).join("|"));
    return z;
  },
  fromString: function(query_represented_as_a_string){
    var split_query = query_represented_as_a_string.split("|");
    var query_components = _.object(_.zip(this.fieldOrder(), split_query));

    _(_(query_components).keys()).each(function(key){ if(typeof query_components[key] === "undefined") { query_components[key] = ''; } })
    console.log(query_components)
    this.set(query_components);
  },

  // this converts a URL-style query like "analysis;MyEmotiveWordsAnalysis;cuss_words" into an actual query_string.
  // if the query after `search/` in the URL doesn't begin with `analysis;` then this is just a pass-thru.
  queryOrAnalysis: function(query_string){
    var analysis_match_obj = (typeof query_string === "undefined" ? '' : query_string).match(/analysis;([A-Za-z]+);([A-Za-z_]+)/);
    if(analysis_match_obj){
      return (new Stevedore.Models[analysis_match_obj[1]]).searches()[analysis_match_obj[2]].join(" OR ");
    }else {
      return query_string;
    }
  },

  // a semi-hacky way of generating a CSV from a result set.
  toCSV: function(cb){
    delimiter = ",";
    var max_page_count = 20;
    var keys = null, 
        headers = null;

    var resp_counter = 0;
    while (!this.get('hit_count') || ( (this.get('pageNum') * Stevedore.max_hits) < this.get('hit_count')) ){
      console.log("getting more docs for CSV, hit count was", this.get('hit_count'), "has", this.get('pageNum') * Stevedore.max_hits  );
      
      resp_counter += 1;
      this.search(function(){ 
        resp_counter -= 1;
        if (resp_counter == 0){
          if(keys === null){
            keys = _(JSON.flatten(Stevedore.document_collection.at(0).attributes)).keys();
            var _keys = _(keys);
            console.log('set keys', keys);
            headers = keys.join(delimiter);
          }

          var rows = Stevedore.document_collection.map(function(obj){ return _keys.map(function(key){ return "\"" + (obj.get(key) || '').toString().replace(/"/g, '\'') + "\"" }) })
          if(cb) cb(headers + "\n" + _(rows).map(function(row){ return row.join(delimiter)}).join("\n"));
        }
      });

      this.set('pageNum', this.get('pageNum') + 1);
      if(this.get('pageNum') > max_page_count){
        alert("Too many documents, try narrowing your search; returning CSV of only " + (Stevedore.max_hits * max_page_count).format());
        break;
      }
    }
  },


  // you need to define these in QueryBuilder
  toQuery: function(){
    console.log('default toQuery');
    return {};
  },
  fieldOrder: function(){
    return ['query_string'];
  },  
  likeActuallyCreate: function(){
    return this;
  },

  // Optional: you may define this in QueryBuilder
  toSort: function(){
    var sort_query = ["_score"];
    return sort_query;
  }
});
