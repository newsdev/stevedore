Stevedore.Views.AllDocumentsAnalysis = Backbone.View.extend({
  initialize: function(){
    _.bindAll(this, 'render');

    this.model = new Stevedore.Models.AllDocumentsAnalysis();
    this.listenTo(this.model, 'stevedore:analysis-loaded', this.render);
    this.model.fetch();
  },

  render: function(){
    var self = this;
    this.$el.show();
    this.$el.empty();

    this.$el.html('<div class="alldocs"><h2>All Documents</h2><ol></ol>loading...</div>')

    _.each(this.model.get('document_names'), function(doc_name) {
      // bleh
      var html = '<li><h4><a href=/search/'+Stevedore.project+'/document/' +doc_name["_id"] +'>'+doc_name.fields["title"] || doc_name.fields["source_url"] +'</a></h4></li>';
      self.$el.find('.alldocs > ol').append(html);
    });
  },

  build_endpoint: function(to, from) {
    return '/search/' + Stevedore.project + '/search/|' + from + '|' + to + '|||';
  }
});
