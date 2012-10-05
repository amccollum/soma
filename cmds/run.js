// Generated by CoffeeScript 1.3.3
var domain, fs, http, mime, soma, zlib,
  __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

domain = require('domain');

http = require('http');

fs = require('fs');

zlib = require('zlib');

mime = require('../lib/node/lib/mime');

soma = require('soma');

exports.run = function() {
  var serverDomain, zlibCache;
  zlibCache = {
    gzip: {},
    deflate: {}
  };
  serverDomain = domain.create();
  return serverDomain.run(function() {
    var port, server;
    server = http.createServer(function(request, response) {
      var requestDomain;
      requestDomain = domain.create();
      requestDomain.add(request);
      requestDomain.add(response);
      requestDomain.on('error', function(err) {
        console.error('Error', request.url, (err != null ? err.stack : void 0) || err);
        try {
          response.statusCode = 500;
          response.end('Error occurred, sorry.');
          return response.on('close', function() {
            return requestDomain.dispose();
          });
        } catch (err) {
          console.error('Error sending 500', request.url, err);
          return requestDomain.dispose();
        }
      });
      return requestDomain.run(function() {
        var acceptEncoding, content, contentEncoding, context, m, send, _ref;
        if (request.url in soma.files) {
          content = soma.files[request.url];
          contentEncoding = 'identity';
          send = function(err, content) {
            var contentLength;
            if (err) {
              throw err;
            }
            if (typeof content === 'string') {
              contentLength = Buffer.byteLength(content);
            } else {
              contentLength = content.length;
            }
            response.setHeader('Content-Type', mime.lookup(request.url));
            response.setHeader('Content-Length', contentLength);
            response.setHeader('Content-Encoding', contentEncoding);
            return response.end(content);
          };
          acceptEncoding = request.headers['accept-encoding'] || '';
          if (soma.config.compress && (m = acceptEncoding.match(/\b(deflate|gzip)\b/))) {
            contentEncoding = m[1];
            if (_ref = request.url, __indexOf.call(zlibCache[contentEncoding], _ref) >= 0) {
              return send(null, zlibCache[contentEncoding][request.url]);
            } else {
              return zlib[contentEncoding](content, send);
            }
          } else {
            return sendContent(null, content);
          }
        } else {
          context = new soma.Context(request, response, soma.scripts);
          return context.begin();
        }
      });
    });
    port = process.env.PORT || soma.config.port || 8000;
    server.listen(port);
    return console.log("Soma listening on port " + port + "...");
  });
};
