// a QueryBuilder should take no arguments
// using jQuery (or whatever) find the values of the fields in search_form
// and return an instance of the Search model (/app/models/Search.js)

Stevedore.QueryBuilder = {
  toQuery: function(){
    var facets = [];
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
                must: facets,
                // should: {},
                // must_not: {}

              }
    }

    return {
      filtered: {
        query: query_section,
        filter: filter_section,
      }
    }
  },
  toString: function(){
    var repr = [];
    repr.push(this.get('query_string'));
    repr.concat(this.get('facets') || []);
    return encodeURIComponent(repr.join("|"));
  },
  // fromString: function(query_represented_as_a_string){
  //   var split_query = query_represented_as_a_string.split("|");
  //   var query_string = split_query.shift();
  //   var facets = split_query;
  //   this.set({query_string: query_string, facets: facets})
  // },
  likeActuallyCreate: function(form_el){
    this.set('query_string', $(form_el).find('#search').val());
    this.set('facets', []);
  },
  toSort: function(form_el){
    var sort_query = ["_score"];
    return sort_query;
  },
  source_fields: function(){
    return {"exclude": ["analyzed.body", "file.file"],}
  }  
};
