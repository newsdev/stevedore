Stevedore.Views.SavedSearches = Backbone.View.extend({
  events: {
    'click .clear-saved-searches': 'clear',
    'click .show-saved-searches': 'showSavedSearches',
    'mouseleave': 'hideSavedSearches'
  },
  initialize: function(){
    _.bindAll(this, 'render', 'clear');
    this.listenTo(Stevedore.saved_searches_collection, 'add', _.debounce(this.render, 0.5)); 
    this.listenTo(Stevedore.saved_searches_collection, 'change', this.render);
    this.listenTo(Stevedore.saved_searches_collection, 'remove', this.render);
    this.listenTo(Stevedore.saved_searches_collection, 'reset', this.render);
  },
  render: function(){
    this.$el.find("#saved-searches").empty();
    Stevedore.saved_searches_collection.each(_.bind(function(savedSearch){
      this.$el.find("#saved-searches").append(new Stevedore.Views.SavedSearch({model: savedSearch}).render().el );
    }, this));
    Stevedore.saved_searches_collection.save();

    if (Stevedore.saved_searches_collection.length === 0) {
      this.$el.hide();
    } else {
      this.$el.show();
    }
  },
  clear: function(){
    Stevedore.saved_searches_collection.localStorage._clear(); // localStorage adapter sucks
    Stevedore.saved_searches_collection.fetch();

    Stevedore.router.navigate(Stevedore.config.use_slash_based_routing ? '' : (Stevedore.project + "/") + '');
    this.render();
  },
  showSavedSearches: function(e) {
    this.render();
    this.$el.find('#saved-searches').show();
    return false;
  },
  hideSavedSearches: function() {
    this.$el.find('#saved-searches').hide();
  }
});
