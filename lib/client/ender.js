// Generated by CoffeeScript 1.4.0
var $, soma,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

soma = require('soma');

$ = ender;

soma.config.engine = 'browser';

$.ender({
  enhance: function(context) {
    return $(document).enhance(context);
  }
});

$.ender({
  enhance: function(context) {
    var form, name, value, view, views, _i, _j, _len, _len1, _ref, _ref1;
    views = [];
    _ref = soma.views;
    for (name in _ref) {
      if (!__hasProp.call(_ref, name)) continue;
      value = _ref[name];
      $(value.prototype.selector, this).each(function() {
        return views.push(new soma.views[name]({
          el: this,
          context: context
        }));
      });
    }
    for (_i = 0, _len = views.length; _i < _len; _i++) {
      view = views[_i];
      view.emit('complete');
    }
    _ref1 = $('form');
    for (_j = 0, _len1 = _ref1.length; _j < _len1; _j++) {
      form = _ref1[_j];
      $(form).append("<input type=\"hidden\" name=\"_csrf\" value=\"" + ($.jar.get('_csrf', {
        raw: true
      })) + "\" />");
    }
  },
  outerHTML: function(html) {
    if (html) {
      return this.each(function() {
        return $(this).replaceWith(html);
      });
    } else {
      return this[0].outerHTML || new XMLSerializer().serializeToString(this[0]);
    }
  }
}, true);

$('document').ready(function() {
  var context;
  context = new soma.BrowserContext(document.location.pathname);
  $.enhance(context);
  if (history.pushState) {
    $('document').one('load', function() {
      return history.replaceState(true, '', document.location);
    });
    window.onpopstate = function(event) {
      if (!event.state) {
        return;
      }
      return soma.load(document.location.pathname);
    };
    $('a[data-precache != "true"]:local-link(0)').each(function() {
      var path;
      path = this.pathname;
      return $(this).bind('click', function(event) {
        history.pushState(true, '', path);
        soma.load(path);
        event.stop();
      });
    });
    return $('a[data-precache = "true"]:local-link(0)').each(function() {
      $(this).bind('click', soma.precache(this.pathname));
    });
  }
});

soma.precache = function(path) {
  var context;
  if (history.pushState) {
    context = soma.load(path, true);
    return function(event) {
      history.pushState({}, '', context.path);
      context.render();
      if (event) {
        event.stop();
      }
    };
  } else {
    return function(event) {
      if (this.pathname !== path) {
        document.location = path;
        if (event) {
          return event.stop();
        }
      }
    };
  }
};

soma.load = function(path, lazy) {
  var context;
  context = new soma.BrowserContext(path, lazy);
  context.begin();
  return context;
};

soma.Chunk = (function(_super) {

  __extends(Chunk, _super);

  function Chunk() {
    return Chunk.__super__.constructor.apply(this, arguments);
  }

  Chunk.prototype.complete = function() {
    this.el || (this.el = $(this.html));
    return this.el.data('view', this);
  };

  Chunk.prototype.loadElement = function(tag, attributes, text, callback) {
    var done, el, url, urlAttr,
      _this = this;
    urlAttr = (tag === 'img' || tag === 'script' ? 'src' : 'href');
    url = attributes[urlAttr];
    if (url) {
      el = $("head [" + urlAttr + "=\"" + url + "\"], head [data-" + urlAttr + "=\"" + url + "\"]");
    }
    if (el && el.length) {
      if ('type' in attributes && attributes.type !== el.attr('type')) {
        el.detach().attr('type', attributes.type).appendTo($('head'));
      }
    } else {
      el = $(document.createElement(tag));
      if ('type' in attributes) {
        if (!url) {
          el.text(text);
        } else if (attributes.type === 'text/javascript') {
          el.attr('defer', 'defer');
        } else {
          el.attr("data-" + urlAttr, url);
          delete attributes[urlAttr];
          $.ajax({
            method: 'GET',
            url: "" + url,
            type: 'html',
            success: function(text) {
              el.text(text);
              return el.trigger('load');
            },
            error: function(xhr, status, e, data) {
              return el.trigger('error');
            }
          });
        }
        $('head').append(el);
      }
      if (url && url.substr(0, 5) !== 'data:') {
        el.attr('data-loading', 'loading');
        el.bind('load error', function() {
          return el.removeAttr('data-loading');
        });
      }
      el.attr(attributes);
    }
    if (el.attr('data-loading')) {
      done = this.wait(callback);
      el.bind('load', function() {
        return done(el);
      });
      el.bind('error', function() {
        _this.emit('error', 'loadElement', tag, attributes, text);
        return done(el);
      });
    } else if (callback) {
      callback(el);
    }
    return el;
  };

  Chunk.prototype.setTitle = function(title) {
    return $('title').text(title);
  };

  Chunk.prototype.setIcon = function(attributes) {
    var el;
    if (typeof attributes === 'string') {
      attributes = {
        href: attributes
      };
    }
    attributes.rel || (attributes.rel = 'icon');
    attributes.type || (attributes.type = 'image/png');
    el = $("link[rel=\"" + attributes.rel + "\"][href=\"" + attributes.href + "\"]");
    if (!el.length) {
      el = $(document.createElement('link'));
      $('head').append(el);
    }
    el.attr(attributes);
    return el;
  };

  Chunk.prototype.setMeta = function(attributes, value) {
    var el, name;
    if (typeof attributes === 'string') {
      name = attributes;
      attributes = {
        name: name,
        value: value
      };
    }
    el = $("meta[name=\"" + attributes.name + "\"]");
    if (!el.length) {
      el = $(document.createElement('meta'));
      $('head').append(el);
    }
    el.attr(attributes);
    return el;
  };

  Chunk.prototype.loadScript = function(attributes, callback) {
    if (typeof attributes === 'string') {
      attributes = {
        src: attributes
      };
    }
    attributes.type = 'text/javascript';
    return this.loadElement('script', attributes, null, callback);
  };

  Chunk.prototype.loadStylesheet = function(attributes) {
    if (typeof attributes === 'string') {
      attributes = {
        href: attributes
      };
    }
    attributes.type = 'text/css';
    attributes.rel = 'stylesheet';
    return this.loadElement('link', attributes);
  };

  Chunk.prototype.loadTemplate = function(attributes) {
    var el;
    if (typeof attributes === 'string') {
      attributes = {
        src: attributes
      };
    }
    attributes.type = 'text/html';
    el = this.loadElement('script', attributes);
    el.toString = function() {
      return el.html();
    };
    return el;
  };

  Chunk.prototype.loadImage = function(attributes) {
    var el;
    if (typeof attributes === 'string') {
      attributes = {
        src: attributes
      };
    }
    el = this.loadElement('img', attributes);
    el.toString = function() {
      return el.outerHTML();
    };
    return el;
  };

  Chunk.prototype.loadData = function(options) {
    var done, result, _error, _success,
      _this = this;
    result = {};
    done = this.wait();
    _success = options.success;
    _error = options.error;
    options.headers || (options.headers = {});
    options.headers['X-CSRF-Token'] = this.cookies.get('_csrf', {
      raw: true
    });
    options.success = function(data) {
      var key, _i, _len;
      for (_i = 0, _len = data.length; _i < _len; _i++) {
        key = data[_i];
        result[key] = data[key];
      }
      if (_success) {
        _success(data);
      }
      return done();
    };
    options.error = function(xhr) {
      if (_error) {
        _error(xhr.status, xhr.response, options);
      } else {
        _this.emit('error', 'loadData', xhr.status, xhr.response, options);
      }
      return done();
    };
    $.ajaj(options);
    return result;
  };

  return Chunk;

})(soma.Chunk);

soma.BrowserContext = (function(_super) {

  __extends(BrowserContext, _super);

  function BrowserContext(path, lazy) {
    this.path = path;
    this.lazy = lazy;
    this.cookies = $.jar;
  }

  BrowserContext.prototype.begin = function() {
    var result, _i, _len, _ref;
    this.results = soma.router.run(this.path, this);
    if (this.results && this.results.length) {
      _ref = this.results;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        result = _ref[_i];
        if (result instanceof soma.Chunk) {
          this.send(result);
        }
      }
    } else {
      if (!this.lazy) {
        this.render();
      }
    }
  };

  BrowserContext.prototype.send = function(chunk) {
    if (!(chunk instanceof soma.Chunk)) {
      throw new Error('Must send chunks on the client');
    } else if (this.chunk) {
      throw new Error('Cannot send multiple chunks');
    }
    this.chunk = chunk;
    while (this.chunk.meta) {
      this.chunk = this.chunk.meta();
    }
    this.chunk.load(this);
    if (!this.lazy) {
      this.render();
    }
  };

  BrowserContext.prototype.render = function() {
    var done,
      _this = this;
    this.lazy = false;
    if (!this.chunk) {
      document.location = this.path;
      return;
    }
    done = function() {
      _this.chunk.emit('render');
      $('body').html(_this.chunk.html);
      return $.enhance(_this);
    };
    if (this.chunk.status === 'complete') {
      done();
    } else {
      this.chunk.on('complete', done);
    }
  };

  BrowserContext.prototype.go = function(path, replace) {
    if (history.pushState) {
      if (!this.lazy) {
        if (replace) {
          history.replaceState(true, '', path);
        } else {
          history.pushState(true, '', path);
        }
      }
      if (this.chunk) {
        this.chunk.emit('halt');
        this.chunk = null;
      }
      this.path = path;
      this.begin();
    } else {
      document.location = path;
    }
  };

  return BrowserContext;

})(soma.Context);
