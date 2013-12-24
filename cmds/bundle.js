// Generated by CoffeeScript 1.6.3
var Bundle, crypto, fs, soma;

crypto = require('crypto');

fs = require('fs');

soma = require('soma');

exports.bundle = function() {
  var bundle, bundles, mapping, sources, url, _i, _len, _ref;
  bundles = {};
  mapping = {};
  fs.mkdirSync('bundles', 0x1c0);
  _ref = soma.config.bundles;
  for (_i = 0, _len = _ref.length; _i < _len; _i++) {
    sources = _ref[_i];
    if (typeof sources === 'string') {
      sources = [sources];
    }
    bundle = new Bundle(sources);
    bundle.write('bundles');
    bundles[bundle.hash] = bundle;
    for (url in bundles.files) {
      mapping[url] = bundle.hash;
    }
  }
  fs.writeFileSync('bundles.json', JSON.stringify(mapping), 'utf8');
};

Bundle = (function() {
  function Bundle(sources) {
    var data, sha, url, _ref;
    this.files = {};
    this.hash = null;
    this._collect(sources, soma.tree);
    sha = crypto.createHash('sha1');
    _ref = this.files;
    for (url in _ref) {
      data = _ref[url];
      sha.update(url);
      sha.update(data);
    }
    this.hash = sha.digest('hex');
  }

  Bundle.prototype._collect = function(sources, tree) {
    var branch, part, parts, source, _i, _j, _len, _len1;
    for (_i = 0, _len = sources.length; _i < _len; _i++) {
      source = sources[_i];
      parts = source.split('/');
      branch = tree;
      for (_j = 0, _len1 = parts.length; _j < _len1; _j++) {
        part = parts[_j];
        if (!(part in branch)) {
          branch = null;
          break;
        }
        branch = branch[part];
      }
      if (typeof branch === 'object') {
        this.collect(branch, branch, files);
      } else {
        this.files[branch] = soma.files[branch];
      }
    }
  };

  Bundle.prototype.write = function(dir) {
    var data;
    data = "soma.bundles['" + this.hash + "'] = " + (JSON.stringify(this.files)) + ";";
    fs.writeFileSync("" + dir + "/" + this.hash + ".js", data, 'utf8');
  };

  return Bundle;

})();
