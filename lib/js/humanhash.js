// Public domain software: https://github.com/zacharyvoase/humanhash/blob/master/UNLICENSE

(function() {
  var DEFAULT_HASHER, DEFAULT_WORDLIST, HumanHasher, digest, words;

  digest = '60ad8d0d871b6095808297';

  DEFAULT_WORDLIST = ['ack', 'alabama', 'alanine', 'alaska', 'alpha', 'angel', 'apart', 'april', 'arizona', 'arkansas', 'artist', 'asparagus', 'aspen', 'august', 'autumn', 'avocado', 'bacon', 'bakerloo', 'batman', 'beer', 'berlin', 'beryllium', 'black', 'blossom', 'blue', 'bluebird', 'bravo', 'bulldog', 'burger', 'butter', 'california', 'carbon', 'cardinal', 'carolina', 'carpet', 'cat', 'ceiling', 'charlie', 'chicken', 'coffee', 'cola', 'cold', 'colorado', 'comet', 'connecticut', 'crazy', 'cup', 'dakota', 'december', 'delaware', 'delta', 'diet', 'don', 'double', 'early', 'earth', 'east', 'echo', 'edward', 'eight', 'eighteen', 'eleven', 'emma', 'enemy', 'equal', 'failed', 'fanta', 'fifteen', 'fillet', 'finch', 'fish', 'five', 'fix', 'floor', 'florida', 'football', 'four', 'fourteen', 'foxtrot', 'freddie', 'friend', 'fruit', 'gee', 'georgia', 'glucose', 'golf', 'green', 'grey', 'hamper', 'happy', 'harry', 'hawaii', 'helium', 'high', 'hot', 'hotel', 'hydrogen', 'idaho', 'illinois', 'india', 'indigo', 'ink', 'iowa', 'island', 'item', 'jersey', 'jig', 'johnny', 'juliet', 'july', 'jupiter', 'kansas', 'kentucky', 'kilo', 'king', 'kitten', 'lactose', 'lake', 'lamp', 'lemon', 'leopard', 'lima', 'lion', 'lithium', 'london', 'louisiana', 'low', 'magazine', 'magnesium', 'maine', 'mango', 'march', 'mars', 'maryland', 'massachusetts', 'may', 'mexico', 'michigan', 'mike', 'minnesota', 'mirror', 'mississippi', 'missouri', 'mobile', 'mockingbird', 'monkey', 'montana', 'moon', 'mountain', 'muppet', 'music', 'nebraska', 'neptune', 'network', 'nevada', 'nine', 'nineteen', 'nitrogen', 'north', 'november', 'nuts', 'october', 'ohio', 'oklahoma', 'one', 'orange', 'oranges', 'oregon', 'oscar', 'oven', 'oxygen', 'papa', 'paris', 'pasta', 'pennsylvania', 'pip', 'pizza', 'pluto', 'potato', 'princess', 'purple', 'quebec', 'queen', 'quiet', 'red', 'river', 'robert', 'robin', 'romeo', 'rugby', 'sad', 'salami', 'saturn', 'september', 'seven', 'seventeen', 'shade', 'sierra', 'single', 'sink', 'six', 'sixteen', 'skylark', 'snake', 'social', 'sodium', 'solar', 'south', 'spaghetti', 'speaker', 'spring', 'stairway', 'steak', 'stream', 'summer', 'sweet', 'table', 'tango', 'ten', 'tennessee', 'tennis', 'texas', 'thirteen', 'three', 'timing', 'triple', 'twelve', 'twenty', 'two', 'uncle', 'undress', 'uniform', 'uranus', 'utah', 'vegan', 'venus', 'vermont', 'victor', 'video', 'violet', 'virginia', 'washington', 'west', 'whiskey', 'white', 'william', 'winner', 'winter', 'wisconsin', 'wolfram', 'wyoming', 'xray', 'yankee', 'yellow', 'zebra', 'zulu'];

  HumanHasher = (function() {
    var S4, bytes, compress, uid, xor;

    function HumanHasher(wordlist) {
      if (wordlist == null) wordlist = DEFAULT_WORDLIST;
      if (wordlist.length !== 256) throw "Wordlist must have exactly 256 items";
      this.wordlist = wordlist;
    }

    bytes = function(digest) {
      var el, i, zips, _i, _len, _len2, _results;
      zips = [];
      for (i = 0, _len = digest.length; i < _len; i++) {
        el = digest[i];
        if (i !== (digest.length - 1) && i % 2 === 0) {
          zips.push([digest[i], digest[i + 1]]);
        }
      }
      _results = [];
      for (_i = 0, _len2 = zips.length; _i < _len2; _i++) {
        el = zips[_i];
        _results.push(parseInt(el.join(''), 16));
      }
      return _results;
    };

    xor = function(iterable) {
      var el, start, _i, _len;
      start = 0;
      for (_i = 0, _len = iterable.length; _i < _len; _i++) {
        el = iterable[_i];
        start ^= el;
      }
      return start;
    };

    compress = function(bytes, target) {
      var el, i, last, seg_size, segments;
      seg_size = parseInt(bytes.length / target);
      segments = (function() {
        var _results;
        _results = [];
        for (i = 0; 0 <= target ? i < target : i > target; 0 <= target ? i++ : i--) {
          _results.push(bytes.slice(i * seg_size, ((i + 1) * seg_size)));
        }
        return _results;
      })();
      last = segments[target - 1];
      last.push.apply(last, bytes.slice(target * seg_size));
      segments = (function() {
        var _i, _len, _results;
        _results = [];
        for (_i = 0, _len = segments.length; _i < _len; _i++) {
          el = segments[_i];
          _results.push(xor(el));
        }
        return _results;
      })();
      return segments;
    };

    S4 = function() {
      return (((1 + Math.random()) * 0x10000) | 0).toString(16).substring(1);
    };

    uid = function() {
      return S4() + S4() + "" + S4() + "" + S4() + "" + S4() + "" + S4() + S4() + S4();
    };

    HumanHasher.prototype.humanize = function(hexdigest, words, separator) {
      var compressed, el, in_bytes;
      if (words == null) words = 4;
      if (separator == null) separator = '-';
      in_bytes = bytes(hexdigest);
      compressed = compress(in_bytes, words);
      return ((function() {
        var _i, _len, _results;
        _results = [];
        for (_i = 0, _len = compressed.length; _i < _len; _i++) {
          el = compressed[_i];
          _results.push(this.wordlist[el]);
        }
        return _results;
      }).call(this)).join("-");
    };

    HumanHasher.prototype.uuid = function() {
      digest = uid();
      return [this.humanize(digest), digest];
    };

    return HumanHasher;

  })();
  window.HumanHasher = HumanHasher;

}).call(this);
