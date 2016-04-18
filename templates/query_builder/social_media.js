// a QueryBuilder should take no arguments
// using jQuery (or whatever) find the values of the fields in search_form
// and return an instance of the Search model (/app/models/Search.js)

Stevedore.QueryBuilder = {
  toQuery: function(){
    var query_section =  { //TODO: make this a bool, add other scoring-relevant stuff.
                            bool: {
                              should: [
                                {
                                  query_string: {
                                    query: this.get('query_string').length ? this.queryOrAnalysis(this.get('query_string')) : '*',
                                    fields: ["_all", "analyzed.body.snowball"],
                                    analyzer: "snowball"
                                  }
                                },
                                {
                                  query_string: {
                                    query: this.get('query_string').length ? this.queryOrAnalysis(this.get('query_string')) : '*',
                                    fields: ["_all", "analyzed.body.snowball"],
                                  }
                                }
                              ]
                            }
                    };
    var filter_section = {
              bool:{
                must: [{exists: {field: 'body'}}],
                // should: {},
                // must_not: {}

              }
    }

    var date_range_filter = {
      range: { }
    };
    if( (this.get('date_start') && this.get('date_start').length) || (this.get('date_end') && this.get('date_end').length) ){
      date_range_filter['range']['created_at'] = {"gte": this.get('date_start').length ? this.get('date_start') : new Date(0).toISOString(),
                                                    "lte": this.get('date_end').length   ? this.get('date_end') : new Date().toISOString() }
      filter_section.bool.must = filter_section.bool.must.concat([date_range_filter]);
    }
  
    if(this.get('deleted') && (this.get('deleted') === true || this.get('deleted') === "true")   ){
      filter_section.bool.must = filter_section.bool.must.concat([{term: {deleted: true}}]);
    }

    if(this.get('platform') && this.get('platform').length ){
      filter_section.bool.must = filter_section.bool.must.concat([{terms: {platform: this.get('platform').split(",") }}]);
    }
    if(this.get('candidate_name') && this.get('candidate_name').length ){
      if(this.get('candidate_name') === "include-dropouts"){
        // do nothing, so we don't filter on candidate_name at all.
      }else{
        filter_section.bool.must = filter_section.bool.must.concat([{term: {candidate_name: this.get('candidate_name') }}]);
      }
    }else{
      filter_section.bool.must = filter_section.bool.must.concat([{terms: {candidate_name: [
        "Bernard Sanders", "Marco Rubio", "Hillary Rodham Clinton", 
        "John Kasich", "Ted Cruz", "Gary Johnson", "Donald Trump" ]}}]);
    }


    return {
      filtered: {
        query: query_section,
        filter: filter_section,
      }
    }
  },

  // just a list of fields that you want persisted in search history and in URLs
  // they'll be preserved in this order, so you might want to order them in order 
  // of decreasing importannce
  fieldOrder: function(){
    return ['query_string', 'deleted', 'sort', 'candidate_name', 'platform', 'date_start', 'date_end'];
  },

  // TODO: these could potentially be moved into the default, shared version of this.
  toString: function(){
    var z =encodeURIComponent(_(this.fieldOrder()).map(_.bind(function(field){
      return typeof this.get(field) === 'undefined' ? '' : this.get(field);
    }, this)).join("|"));
    return z;
  },
  // fromString: function(query_represented_as_a_string){
  //   var split_query = query_represented_as_a_string.split("|");
  //   var query_string = split_query.shift();
  //   var facets = split_query;
  //   this.set({query_string: query_string, facets: facets})
  // },
  likeActuallyCreate: function(form_el){
    this.set('query_string', $(form_el).find('#search').val());
    this.set('deleted', !!$(form_el).find('#deleted:checked').val())
    this.set('sort', $(form_el).find('#sort').length && $(form_el).find('#sort').val() ? $(form_el).find('#sort').val() : '');

    this.set('candidate_name', $(form_el).find('#candidate-select option:selected').val() || '')
    var platforms = $.makeArray($(form_el).find('#platform-checkboxes input:checked').map(function(i, el){ return $(el).val() }));
    this.set('platform', platforms.join(",") );

    this.set('date_start', $(form_el).find('#date_start').length && $(form_el).find('#date_start').data('pikaday').getDate() ? $(form_el).find('#date_start').data('pikaday').getDate().toISOString() : ''); 
    this.set('date_end', $(form_el).find('#date_end').length && $(form_el).find('#date_end').data('pikaday').getDate() ? $(form_el).find('#date_end').data('pikaday').getDate().toISOString() : '');
  },

  toSort: function(form_el){
    var sort_val = this.get('sort');
    console.log('sort-val', sort_val)
    var sort_query = [];
    if(sort_val && sort_val.length){
      if(sort_val.indexOf(';') > -1){
        var split = sort_val.split(';');
        var new_obj = {};
        new_obj[split[0]] = split[1];
        sort_query.push(new_obj);
      }else{
        sort_query.push(sort_val)
      }
    }
    sort_query.push("_score")
    return sort_query;
  }
};
