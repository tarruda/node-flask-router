## flask-router

  Routing system for node.js/connect based on Flask(http://flask.pocoo.org/).

#### Installation

```sh
npm install flask-router
```

#### Usage

```js
var http = require('http')
  , router = require('flask-router')()
  , server = http.createServer(router.route);
```

  It can also be used as a connect/express middleware:
  
```js
var connect = require('connect')
  , app = connect()
  , router = require('flask-router')()
  , app.use(router.route);
```
 
  Then routes can be added like this:
  
```js
router.get('/users/<str(max=5,min=2):id>', function (req, res) {
  console.log(req.params.id);
  res.end();
});

router.post('/users/<str(len=7):id>', function (req, res) {
  console.log(req.params.id);
  res.end();
});

router.put('/customers/<id>', function (req, res) {
  console.log(req.params.id);
  res.end();
});
```

  Can assign multiple handler functions to the same rule:

```js
router.get('/get/<uuid:id>'
, function(req, res, next) {
  res.write('part1');
  next();
}, function(req, res, next) {
  res.write('part2');
  next();
});

router.get('/get/<uuid:id>', function(req, res) {
  res.write('part3');
  res.end();
});
// All three handlers will be executed when the url match, so the final
// response will be 'part1part2part3'
```

  Custom parameter parsers can be registered(these are known as 'converters'
  in Flask/Werkzeug): 

```js
router.registerParser('options', function(str) {
  var rv = {};
    , options = str.split('/')
    , i, len, kv, key, value;
  for (i = 0, len = options.length; i < len; i++) {
    option = options[i];
    kv = option.split('=');
    key = kv[0], value = kv[1];
    rv[key] = value;
  }
  return rv;
});

router.get('/queryable/<options:query>', function(req, res) {
  console.log(JSON.stringify(req.params.query));
  res.end();
});
// If '/queryable/gt=5/lt=10/limit=20' was requested,
// the output would be {"limit":"20","gt":"5","lt":"10"}
```

  Can be used to write middlewares, just like express routes:

```js
// anyone can access public files
router.get('/public/<path:file>', function(req, res) {
  res.write(req.params.file);
  res.end();
});

// will match any path that starts with /private
router.all('/private/<path:path>', function(req, res, next) {
  if (req.headers['x-user']) {
    req.loggedIn = true;
    next('route');
  } else {
    next();
  }
});
router.all('/private/<path:path>', function(req, res) {
  res.writeHead(401); // not authorized
  res.end();
});

// the next two handlers will only be executed if the user is
// authorized(in this case, the request must have x-user header)
router.post('/private/addpost/<title>', function(req, res) {
  // req.loggedIn === true
  res.write('post added'));
  res.end();
});

router.get('/private/posts', function(req, res) {
  // req.loggedIn === true
  res.write(db.query('posts')');
  res.end();
});
```

  RegExps can also be used as rules:

```js
router.get(/^\/posts\/(\d+)/i, function(req, res) {
  // Will match /posts/5 or /POSTs/32422
  // captured text can be accessed by index on req.params
  console.log('Id:', req.params[0])
  res.end()
})
```

  See tests for more examples.
