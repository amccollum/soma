// Generated by CoffeeScript 1.3.3
var fs, soma;

fs = require('fs');

soma = require('soma');

exports.init = function() {
  var defaults, key, value, _results;
  defaults = {
    compress: true,
    inlineScripts: false,
    inlineStylesheets: false,
    app: ['app'],
    api: ['api']
  };
  soma.config = JSON.parse(fs.readFileSync('package.json')).soma;
  _results = [];
  for (key in defaults) {
    value = defaults[key];
    if (!(key in soma.config)) {
      _results.push(soma.config[key] = value);
    } else {
      _results.push(void 0);
    }
  }
  return _results;
};