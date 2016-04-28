
Stevedore.Views.Search = Backbone.View.extend({
  //el: to be defined live, since it exists on load.

  events: {
    "submit": 'search',
    'click': 'closeItem',
    "click .download-as-csv": 'downloadCSV'    
  },
  options: {},
  option_template_string: '<option class="stevedore-autogen" value="{{= key }}" {{= (search[field] === key) ? "selected" : "" }}>{{= key }}</option>',

  initialize: function(){
    _.bindAll(this, 'search', 'render', 'renderHits', 'createSearch', 'loadSearch', 'downloadCSV', 'scrollTo');
    this.setTemplate();
  },
  setTemplate: function(){
    this.template = !(_.isUndefined(Stevedore.template_names) || _.isUndefined(Stevedore.templates[Stevedore.template_names['search_form']].search_form)) ? Stevedore.templates[Stevedore.template_names['search_form']].search_form : _.template('<div></div>');
  },

  closeItem: function(){
    if(Stevedore.detail_view && Stevedore.detail_view.$el.is(':visible')){
      Stevedore.detail_view.close();
    }
  },

  // TODO: dedupe this.
  search: function(){
    var new_search = new Stevedore.Models.Search();
    new_search.likeActuallyCreate(this.$el);
    Stevedore.document_collection.reset([]);

    var search = this.createSearch(new_search);

    Stevedore.router.navigate( (Stevedore.config.use_slash_based_routing ? '' : Stevedore.project + "/") + "search/" + search.toString());
    //only scroll to the top of results on a new search (not loading new results and not loading a search from the URL)
    if(!Stevedore.document_collection.size()){
      this.listenToOnce(this.model, "stevedore:search-done", this.scrollTo);
    }

    search.search();
    return false;
  },

  createSearch: function(new_search){
    this.options = new_search.attributes;

    // don't repeat selections in saved.
    if(Stevedore.saved_searches_collection.size() == 0 || !_.isEqual(
        _.pick(new_search.attributes, 'query_string', 'facets'),
        _.pick(Stevedore.saved_searches_collection.at(0).attributes, 'query_string', 'facets'))
      ){
      Stevedore.saved_searches_collection.create(new_search);
    }
    this.model = new_search;
    this.listenTo(this.model, "stevedore:search-start", this.renderHits);
    this.listenTo(this.model, "stevedore:search-done", this.renderHits);
    this.render();
    $('.hit-count-container').hide();
    return new_search;
  },
  scrollTo: function(){
    // TODO: only do if the search is new, not if we're asking for more results.
    // and if we're not coming from the
    $(window).scrollTop($('.hit-count-container').offset().top);
  },

  loadSearch: function(search){
    search.set('searched_at', new Date());
    search.save();
    Stevedore.document_collection.reset([]);

    Stevedore.router.navigate( (Stevedore.config.use_slash_based_routing ? '' : Stevedore.project + "/") + "search/" + search.toString());
    this.options = search.attributes;
    this.model = search;
    this.listenTo(this.model, "stevedore:search-start", this.renderHits);
    this.listenTo(this.model, "stevedore:search-done", this.renderHits);
    // for a "loaded" search, we don't want to scroll to results when it's done
    // because this may just be a link to the search page with the query in the URL.

    search.search();
    this.render();
    return false;
  },

  downloadCSV: function(){
    this.model.toCSV(function(csvData){
      filename = "fl_contracts.xls"
      var blob = new Blob([csvData], { type: 'text/csv;charset=utf-8;' });
      if (navigator.msSaveBlob) { // IE 10+
          navigator.msSaveBlob(blob, filename);
      } else {
          var link = document.createElement("a");
          if (link.download !== undefined) { // feature detection
              // Browsers that support HTML5 download attribute
              var url = URL.createObjectURL(blob);
              link.setAttribute("href", url);
              link.setAttribute("download", filename);
              link.style.visibility = 'hidden';
              document.body.appendChild(link);
              link.click();
              document.body.removeChild(link);
          }
      }
      return false;
    });
  },

  renderHits: function(){
    if(this.model && !_.isUndefined(this.model.get('hit_count'))){
      if(this.model.get('hit_count') > Stevedore.max_hits){
        $('.hit-count').text("Showing " + Number(Stevedore.document_collection.size()).toLocaleString('en') + " results (of " + Number(this.model.get('hit_count')).toLocaleString('en') + ')');
      }else{
        $('.hit-count').text('Showing all ' + Number(this.model.get('hit_count')).toLocaleString('en') + " result" + (this.model.get('hit_count') != 1 ? 's' : ''));
        $('#paginate').hide();
      }
      $('.hit-count-container').show();
    }
  },

  generateOptions: function(field, select_el){
    // use ElasticSearch to get an aggregation based on this field
    // that is, a listing of all the distinct values of the field
    // then generate the HTML for that.
    $selectEl = $(select_el);
    console.log($(select_el).find('.stevedore-autogen'), $(select_el).find('.stevedore-autogen').length)
    if($(select_el).find('.stevedore-autogen').length > 0){
      return;
    }

    Stevedore.client.search({
      index: Stevedore.es_index,
      body: {
        // Don't need any docs, just the agg results
        size: 0,
        aggs: {
          // Top 10 people who have emailed the most,
          extant_keys: {
            terms: {
              field: field,
              size: 0, // we want all of them!!
              order: {_count: 'desc'}
            }
          },

        }
      }
    }).then(_.bind(function (resp) {
      $selectEl = $(select_el);
      console.log($(select_el).find('.stevedore-autogen'), $(select_el).find('.stevedore-autogen').length)
      if($(select_el).find('.stevedore-autogen').length > 0){
        return;
      }
      var options_html = _(resp.aggregations.extant_keys.buckets).map(_.bind(function(key_obj){
        return _.template(this.option_template_string)(_.extend(key_obj, {'field': field}))
      },this)).join("");

      $(select_el).append($(options_html));
    }, this), function (err) {
      //TODO: error messages
      console.log('option generation errors!')
    });
  },

  render: function(){
    this.setTemplate();
    if (!_.isUndefined(Stevedore.template_names)) this.$el.addClass(Stevedore.template_names['search_form']);

    if(typeof Stevedore.blob_count !== "undefined"){
      this.$el.find('#total-count').text(Stevedore.blob_count + " total docs");
    }
    // with the details of a query object, autofill it back in (from saved searches box)
    this.$el.find("#search-form-container").html(this.template(
      { 
        search: typeof this.model === "undefined" ? {query_string: ''} : this.model.attributes,
        es_index: Stevedore.es_index || '',
        generateOptions: _.bind(this.generateOptions, this)
      }
    ));
    // datepickers need a datepicker class and they'll Just Work.
    // TODO: consider setting minDate, maxDate based on the dataset.
    $('.datepicker').pikaday({ firstDay: 1 });
  },
})
