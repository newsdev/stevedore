// a QueryBuilder should take no arguments
// using jQuery (or whatever) find the values of the fields in search_form
// and return an instance of the Search model (/app/models/Search.js)

Stevedore.QueryBuilder = {


  breakDownEmailAddress: function(address, field_name){
    address = address.toLowerCase(); // this is super important.
    musts = _(_(address.split('@')[0].split(/[^0-9a-zA-Z]/))).select(function(i){ return i.length }).map(function(component){ var t = {term: {}}; t['term'][field_name] = component; return t; });
    shoulds = address.split('@').length > 1 ? _(_(address.split('@')[1].split(/[^0-9a-zA-Z]/))).select(function(i){ return i}).map(function(component){ var t = {term: {}}; t['term'][field_name] = component; return t; }) : [];

    return {must: musts || [], should: shoulds || []}
  },


  toQuery: function(){
    var query_section =  { 
                            bool: {
                              must: [
                                { 
                                  query_string: {
                                    default_field: "_all",
                                    default_operator: "AND",
                                    query: this.get('query_string').length ? this.queryOrAnalysis(this.get('query_string')) : '*', 
                                  } ,
                                  // subject DID go here, but got moved below

                                },
                                 
                              ],
                              should: []
                            }
                    };
    if(this.get('subject') !== undefined && this.get('subject').length){
      console.log('has subj')
      query_section.bool.must.push(
                                {
                                  query_string: {
                                    default_field: "analyzed.metadata.subject",
                                    default_operator: "AND",
                                    query: this.get('subject'),
                                  } ,

                                }
        )
    }

    var from_stuff = this.breakDownEmailAddress(this.get('from'), 'analyzed.metadata.Message-From');
    var to_stuff = _(this.get('to').split(/[ ,;]/)).reduce(_.bind(function(memo, to_addr){
      if(!memo.must) memo.must = [];
      if(!memo.should) memo.should = [];
      to_stuff = this.breakDownEmailAddress(this.get('to'), 'analyzed.metadata.Message-To')
      memo.must = memo.must.concat(to_stuff.must);
      memo.should = memo.should.concat(to_stuff.should);
      return memo;
    }, this), {should: [], must: []});
    
    query_section.bool.must = query_section.bool.must.concat(from_stuff.must);
    query_section.bool.should = query_section.bool.should.concat(from_stuff.should);
    query_section.bool.must = query_section.bool.must.concat(to_stuff.must);
    query_section.bool.should = query_section.bool.should.concat(to_stuff.should);
    // query_section.bool.must.concat(_(this.get('from').split('@')[0].split(/[^0-9a-zA-Z]/)).map(function(component){ return {term: {"analyzed.metadata.Message-To": component}} })) );
    // query_section.bool.should.concat(this.get('from').split('@').length > 1 ? _(this.get('from').split('@')[1].split(/[^0-9a-zA-Z]/)).map(function(component){ return {term: { "analyzed.metadata.Message-To": component}} }) : [])
    var filter_section = {
              bool:{
                must: [],
                // should: [],
                // must_not: []
              }
    }
    if(this.get('date_sent_start').length || this.get('date_sent_end').length){
      var date_filter = {
                          range: {
                            "analyzed.metadata.Creation-Date": {}
                          }
                        };
        date_filter.range["analyzed.metadata.Creation-Date"]["gte"] = this.get('date_sent_start').length ? this.get('date_sent_start') : new Date(0).toISOString()
        date_filter.range["analyzed.metadata.Creation-Date"]["lte"] = this.get('date_sent_end').length ? this.get('date_sent_end') : new Date().toISOString()
      console.log('has date_sent', this.get('date_sent_start'), this.get('date_sent_end'), date_filter)
      filter_section.bool.must.push(date_filter);
    }

    return {
      filtered: {
        query: query_section,
        filter: filter_section, // for now, does nothing. maybe should later.
      }
    }
  },

  // just a list of fields that you want persisted in search history and in URLs
  // they'll be preserved in this order, so you might want to order them in order 
  // of decreasing importannce
  fieldOrder: function(){
    return ['query_string', 'from', 'to', 'subject', 'date_sent_start', 'date_sent_end', 'sort'];
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
  //   this.set(_.object(_.zip(this.fieldOrder(), split_query)));
  // },
  likeActuallyCreate: function(form_el){
    this.set('query_string', $(form_el).find('#search').val() || '');
    this.set('from', $(form_el).find('#from_email').val() || '')
    this.set('to', $(form_el).find('#to_email').val() || '')
    this.set('subject', $(form_el).find('#subject').val() || '')
    this.set('date_sent_start', $(form_el).find('#datesentstart').length && $(form_el).find('#datesentstart').data('pikaday').getDate() ? $(form_el).find('#datesentstart').data('pikaday').getDate().toISOString() : ''); 
    this.set('date_sent_end', $(form_el).find('#datesentend').length && $(form_el).find('#datesentend').data('pikaday').getDate() ? $(form_el).find('#datesentend').data('pikaday').getDate().toISOString() : '');
    this.set('sort', $(form_el).find('#sort').length && $(form_el).find('#sort').val() ? $(form_el).find('#sort').val() : '');
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

    // var qs = $(form_el).find('#search').val()
    // this.set('query_string', typeof qs === 'undefined' ? '' : qs);
    // var from = $(form_el).find('#from_email').val()
    // this.set('from',  typeof from === 'undefined' ? '' : from)
    // var to = $(form_el).find('#to_email').val()
    // this.set('to',  typeof to === 'undefined' ? '' : to)
    // var subj = $(form_el).find('#subject').val()
    // this.set('subject',  typeof subj === 'undefined' ? '' : subj)

