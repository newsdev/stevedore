var stevedore_routes = {};

var routing_prefix = Stevedore.config.use_slash_based_routing ? "" : Stevedore.project + "/";
stevedore_routes[routing_prefix + "document/:document_id"] =  "showDocument" // #help
stevedore_routes[routing_prefix + "search/"] =                "search"    // #search/kiwis    
stevedore_routes[routing_prefix + "search/:query"] =          "search"    // #search/kiwis
stevedore_routes[routing_prefix + "analysis"] =               "emailSenderAnalysis"
stevedore_routes[routing_prefix + "senders"] =                "emailSenderAnalysis"
stevedore_routes[routing_prefix + "alldocs"] =                "allDocumentsAnalysis" 
stevedore_routes[routing_prefix + ""] =                       "index"
if(! Stevedore.config.use_slash_based_routing){
  stevedore_routes[Stevedore.project +       ""] =            "index"
}else{
  stevedore_routes["/"] =                                     "index"
}


Stevedore.SearchApp = Backbone.Router.extend({
  routes: stevedore_routes,

  index: function(){
    Stevedore.search_view = new Stevedore.Views.Search({ el: $('#search-container')[0] } );
    Stevedore.search_view.render();
    Stevedore.document_collection = new Stevedore.Collections.Documents([]);
    Stevedore.results_view = new Stevedore.Views.Results({el: $('#results'), collection: Stevedore.document_collection});
  },

  showDocument: function(document_id) {
    Stevedore.search_view = new Stevedore.Views.Search({ el: $('#search-container')[0] } );
    Stevedore.search_view.render();
    Stevedore.document_collection = new Stevedore.Collections.Documents([]);
    Stevedore.results_view = new Stevedore.Views.Results({el: $('#results'), collection: Stevedore.document_collection});

    var document_model = new Stevedore.Models.Document({id: document_id, human_id: document_id});
    Stevedore.detail_view = new Stevedore.Views.Detail({'el': $('#preview-pane'),
                                                      'model': document_model,
                                                      'attributes': { 'previous': '' } });
    document_model.fetch();
    Stevedore.detail_view.$el.show();
  },

  search: function(encoded_query) {
    // deserialize query and facets
    var query = decodeURIComponent(encoded_query);
    console.log('search router', query);
    Stevedore.search_view = new Stevedore.Views.Search({ el: $('#search-container')[0] } );
    Stevedore.search_view.render();
    Stevedore.document_collection = new Stevedore.Collections.Documents([]);

    // it's possible that the QueryBuilder template that creates Stevedore.Search
    // hasn't loaded yet. (Seems more frequent in Firefox than Chrome)
    // so wait for, if it isn't there yet.
    doTheSearchFromURL = function(){
      var search = new Stevedore.Models.Search();
      search.fromString( query );
      Stevedore.search_view.createSearch(search);
      Stevedore.results_view = new Stevedore.Views.Results({el: $('#results'), collection: Stevedore.document_collection});
      search.search();
    }

    if(typeof Stevedore.Models.Search !== "undefined" ){
      doTheSearchFromURL();
    }else{
      this.listenTo(Stevedore, 'stevedore:querybuilder-loaded', doTheSearchFromURL)
    }

  },

  emailSenderAnalysis: function() {
    Stevedore.analysis_view = new Stevedore.Views.EmailSenderAnalysis({ el: $('#analysis-container')[0] });
    Stevedore.analysis_view.render();
  }
});

