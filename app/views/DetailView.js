Stevedore.Views.Detail = Backbone.View.extend({
  events: {
    'click .close': 'close',
  },
  initialize: function(){
    _.bindAll(this, 'render', 'renderNotFound', 'close', 'pageThru', 'handleClick', 'detail_view_link', 'detail_view_route');
    this.template = _.template($('#detail-container-template').html());
    this.listenTo(this.model, 'change', this.render);
    this.listenTo(this.model, 'notfound', this.renderNotFound);
    this.setTemplate();
    this.model.fetch();
  },
  setTemplate: function(){
    if(typeof Stevedore.template_names === "undefined" || typeof Stevedore.templates === "undefined"){
      return;
    }
    if( (( this.model.get('analyzed') && this.model.get('analyzed').metadata && this.model.get('analyzed').metadata["Content-Type"]) ? this.model.get('analyzed').metadata["Content-Type"] : '').match(  new RegExp(Stevedore.content_types[Stevedore.template_names['detail_view']]) ) ){
      this.project_specific_template = !_.isUndefined(Stevedore.templates[Stevedore.template_names['detail_view']].detail_view) ? Stevedore.templates[Stevedore.template_names['detail_view']].detail_view : _.template('<div></div>');
    }else{
      this.project_specific_template = !_.isUndefined(Stevedore.templates['blob'].detail_view) ? Stevedore.templates['blob'].detail_view : _.template('<div></div>');
    }
  },

  render: function(){
    $('body').off('keydown.blobview');
    $('body').on('keydown.blobview', this.handleClick);
    
    $('.modal').on('hidden.bs.modal', this.close);

    this.setTemplate();
    this.$el.addClass(Stevedore.template_names['detail_view']);
    this.$el.html(this.template(
      _.extend({}, Stevedore.def_obj, this.model.attributes, {tk: 'tk', detail_view_link: this.detail_view_link()} )
    ));
    this.$el.find('#detail-view').html(this.project_specific_template(
      _.extend({}, Stevedore.def_obj, this.model.attributes, {tk: 'tk', detail_view_link: this.detail_view_link()} )
    ));
    this.$el.scrollTop(0);

    // This seems like the wrong place to put this
    this.$el.modal('show');

    return this;
  },

  close: function(){
    this.$el.hide();
    $('body').off('keydown.blobview');
    Stevedore.router.navigate(this.attributes.previous);
    this.$el.empty();
    // Stevedore.results_view.$el.find(".fader").hide();
  },

  handleClick: function(e){
    var keyCode = e.keyCode || e.which;
    if (keyCode == 37 || keyCode == 39){
      this.pageThru(e);
    }else if(keyCode == 27){ //escape
      this.close();
    }
  },

  pageThru: function(e){
    var newIndex;
    var keyCode = e.keyCode || e.which;
    var currentIndex = Stevedore.document_collection.indexOf(this.model);
    if(keyCode == 37){ //left
      newIndex = currentIndex - 1;
      newIndex = newIndex < 0 ? Stevedore.document_collection.size() - 1 : newIndex;
    }else if(keyCode == 39 ){ //right
      newIndex = currentIndex + 1;
      newIndex = newIndex >= Stevedore.document_collection.size() ? 0 : newIndex;
    }
    this.model = Stevedore.document_collection.at(newIndex);
    this.listenTo(this.model, 'change', this.render);    
    this.model.fetch();

    var $result_li = Stevedore.results_view.$el.find("#hit-" + this.model.get('id'));
    console.log($result_li, $result_li.offset().top);
    $('html, body').scrollTop($result_li.offset().top);

    this.render();
  },

  renderNotFound: function(){
    this.project_specific_template = _.template("<div class='modal-body'><h2>Item not found </h2></div>")
    this.render();
    return this;
  },

  // just an internal helper
  detail_view_link: function(){
    return ((Stevedore.config.use_slash_based_routing ? ('/search/' + Stevedore.project) : ("#" + Stevedore.project)) + "/") + this.detail_view_route()
  },

  detail_view_route: function(){
    return "document/" + this.model.get('id')
  }

})
