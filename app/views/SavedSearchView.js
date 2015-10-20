Stevedore.Views.SavedSearch = Backbone.View.extend({
  tagName: 'li',
  className: 'saved-search',
  events: {
    'click': 'loadSearch',
    'click .delete': 'removeSearch'
  },
  initialize: function(){
    this.template = _.template($('#saved-search-template').html());
    _.bindAll(this, 'render', 'loadSearch');
  },
  render: function(){
    this.$el.html(this.template({string_repr: decodeURIComponent(this.model.toString()) } ));
    return this;
  },
  loadSearch: function(e){
    e.preventDefault();
    Stevedore.search_view.loadSearch(this.model);
    return false; // to avoid scrolling to the top 
  }
})
