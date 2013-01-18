connect = require('connect')
createRouter = require('../src/router')

describe 'Rules', ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  router.get '/$imple/.get/pattern$', (req, res) ->
    res.write('body1')
    res.end()

  router.post('/not-a-get/pattern*', -> res.end())

  router.del('/not-a-get/pattern*', -> res.end())

  router.get '/^pattern/that/uses/many/handlers',
    (req, res, next) -> res.write('part1'); next(),
    (req, res, next) -> res.write('part2'); next()

  router.get '/^pattern/that/uses/many/handlers',
    (req, res) -> res.write('part3'); res.end()

  router.get '/cancel',
    (req, res, next) -> res.write('p1'); next(),
    (req, res, next) -> res.write('p2'); res.end(),
    (req, res, next) -> res.write('p3'); next(),
    (req, res, next) -> res.write('p4'); res.end()

  it 'should match simple patterns', (done) ->
    app.request()
      .get('/$imple/.get/pattern$')
      .end (res) ->
        res.body.should.eql('body1')
        done()
    return

  it "should return 405 when pattern doesn't match method", (done) ->
    app.request()
      .get('/not-a-get/pattern*')
      .end (res) ->
        res.statusCode.should.eql(405)
        res.headers['allow'].should.eql('POST, DELETE')
        done()

  it 'should pipe request through all handlers', (done) ->
    app.request()
      .get('/^pattern/that/uses/many/handlers')
      .end (res) ->
        res.body.should.eql('part1part2part3')
        done()

  it 'should cancel pipeline when handler ends the request', (done) ->
    app.request()
      .get('/cancel')
      .end (res) ->
        res.body.should.eql('p1p2')
        done()


describe 'Pathname normalization', ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  router.all /.*/, (req, res) ->
    res.write(req.path)
    res.end()

  it 'should normalize parent path expressions(/dir/..)', (done) ->
    app.request()
      .get('/a/b/c/..')
      .expect '/a/b', ->
        app.request()
          .get('/a/b/c/../..')
          .expect '/a', ->
            app.request()
              .get('/a/b/c/../../..')
              .expect '/', ->
                app.request()
                  .get('/a/b/c/../../../..')
                  .expect '/', ->
                    app.request()
                      .get('/a/../b/c')
                      .expect '/b/c', ->
                        app.request()
                          .get('/a/../../b/c')
                          .expect '/b/c', done

  it 'should normalize current path expressions (/./)', (done) ->
    app.request()
      .get('/a/b/./c')
      .expect '/a/b/c', ->
        app.request()
          .get('/a/./b')
          .expect '/a/b', ->
            app.request()
              .get('/./a')
              .expect '/a', ->
                app.request()
                  .get('/./')
                  .expect '/', ->
                    app.request()
                      .get('/././')
                      .expect '/', done


describe 'Builtin string parser', ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  router.get '/users/<str(max=5,min=2):id>', (req, res) ->
    res.write('range')
    res.end()

  router.get '/users/<str(len=7):id>', (req, res) ->
    res.write('exact')
    res.end()

  router.get '/customers/<id>', (req, res) ->
    res.write(req.params.id)
    res.end()

  it 'should match strings inside range', (done) ->
    app.request()
      .get('/users/foo')
      .end (res) ->
        res.body.should.eql('range')
        done()

  it 'should not match strings outside range', (done) ->
    app.request()
      .get('/users/foobar')
      .expect 404, ->
        app.request()
          .get('/users/f')
          .expect(404, done)

  it 'should match strings of configured length', (done) ->
    app.request()
      .get('/users/1234567')
      .end (res) ->
        res.body.should.eql('exact')
        done()

  it 'should be used when no parser is specified', (done) ->
    app.request()
      .get('/customers/abcdefghijk')
      .end (res) ->
        res.body.should.eql('abcdefghijk')
        done()

  it 'should not match strings containing slashes', (done) ->
    app.request()
      .get('/customers/abcdef/ghijk')
      .expect(404, done)


describe 'Builtin path parser', ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  router.get '/pages/<path:page>/edit', (req, res) ->
    res.write(req.params.page)
    res.end()

  it 'should match normal strings', (done) ->
    app.request()
      .get('/pages/foo/edit')
      .end (res) ->
        res.body.should.eql('foo')
        done()

  it 'should match any number of path segments', (done) ->
    app.request()
      .get('/pages/abc/def/ghi/jkl/edit')
      .end (res) ->
        res.body.should.eql('abc/def/ghi/jkl')
        done()


describe 'Builtin float parser', ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  router.post '/credit/<float(max=99.99,min=1):amount>', (req, res) ->
    res.write(JSON.stringify(req.params.amount))
    res.end()

  it 'should match numbers inside range', (done) ->
    app.request()
      .post('/credit/55.3')
      .end (res) ->
        JSON.parse(res.body).should.eql(55.3)
        done()

  it 'should not match numbers outside range', (done) ->
    app.request()
      .get('/credit/99.999')
      .expect 404, ->
        app.request()
          .get('/credit/0.999')
          .expect(404, done)


describe 'Builtin uuid parser', ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  router.get '/users/<uuid:id>', (req, res) ->
    res.write(req.params.id)
    res.end()

  it 'should match strings that are uuids', (done) ->
    app.request()
      .get('/users/550e8400-e29b-41d4-a716-446655440000')
      .end (res) ->
        res.body.should.eql('550e8400-e29b-41d4-a716-446655440000')
        done()

  it 'should not match strings that are not uuids', (done) ->
    app.request()
      .get('/users/550e8400-e29b-41d4-a716-44665544000')
      .expect(404, done)

  it 'should not care for uppercase letters', (done) ->
    app.request()
      .get('/users/550E8400-E29b-41D4-a716-446655440000')
      .end (res) ->
        res.body.should.eql('550e8400-e29b-41d4-a716-446655440000')
        done()


describe 'Builtin integer parser', ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  router.get '/users/<int(base=16,max=255):id>', (req, res) ->
    res.write(JSON.stringify(req.params.id))
    res.end()

  it 'should match numbers with leading zeros', (done) ->
    app.request()
      .get('/users/000')
      .end (res) ->
        JSON.parse(res.body).should.eql(0)
        done()

  it 'should take numeric base into consideration', (done) ->
    app.request()
      .get('/users/ff')
      .end (res) ->
        JSON.parse(res.body).should.eql(255)
        done()

  it 'should not match numbers outside range', (done) ->
    app.request()
      .get('/users/100')
      .expect(404, done)

  it 'should not match floats', (done) ->
    app.request()
      .get('/users/50.3')
      .expect(404, done)


describe "Builtin 'in' parser", ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  router.get '/posts/<in(t1,t2,t3,true,5.2):tag>', (req, res) ->
    res.write(JSON.stringify(req.params.tag))
    res.end()

  it 'should match if arg is inside list', (done) ->
    app.request()
      .get('/posts/t1')
      .end (res) ->
        JSON.parse(res.body).should.eql('t1')
        done()

  it 'should not match if arg is outside list', (done) ->
    app.request()
      .get('/posts/1')
      .expect(404, done)

  it 'should convert value if needed', (done) ->
    app.request()
      .get('/posts/true')
      .end (res) ->
        JSON.parse(res.body).should.eql(true)
        app.request()
          .get('/posts/5.2')
          .end (res) ->
            JSON.parse(res.body).should.eql(5.2)
            done()


describe 'Optional parts', ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  router.all '/base<path:rest?>', (req, res, next) ->
    if req.params.rest
      # Save the parameters since the match object is reset
      # on each route
      req.rest = req.params.rest
      req.pipe = 'pipe'
      next('route')
    else
      res.write('pipe')
      res.end()

  router.get '/base/path1<n>', (req, res) ->
    res.write(req.pipe)
    res.write(req.params.n)
    res.end()

  router.get '/base/path2/<n?>', (req, res) ->
    res.write(req.pipe)
    if req.params.n
      res.write(req.params.n)
    else
      res.write(req.rest)
    res.end()

  it 'should always use base route', (done) ->
    app.request()
      .get('/base/path1a2')
      .expect 'pipea2', ->
        app.request()
          .get('/base/path1')
          .expect 404, ->
            app.request()
              .get('/base/path2/')
              .expect 'pipe/path2/', ->
                app.request()
                  .get('/base/path2/3')
                  .expect 'pipe3', ->
                    app.request()
                      .get('/base')
                      .expect 'pipe', done


describe 'Accessing branch urls without trailing slash', ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  router.get '/some/branch/url/', (req, res) ->
    res.end()

  it 'should redirect to the correct absolute url', (done) ->
    app.request()
      .set('Host', 'www.google.com')
      .get('/some/branch/url')
      .end (res) ->
        res.statusCode.should.eql(301)
        res.headers['location']
          .should.eql('http://www.google.com/some/branch/url/')
        done()

  it 'should redirect correctly even with a query string', (done) ->
    app.request()
      .set('Host', 'www.google.com')
      .get('/some/branch/url?var1=val1&var2=val2')
      .end (res) ->
        res.statusCode.should.eql(301)
        l = 'http://www.google.com/some/branch/url/?var1=val1&var2=val2'
        res.headers['location'].should.eql(l)
        done()

  it 'should use protocol/port info in the request', (done) ->
    app.request()
      .set('Host', 'www.google.com')
      .set('X-Protocol', 'https')
      .set('X-Port', 8080)
      .get('/some/branch/url?var1=val1')
      .end (res) ->
        res.statusCode.should.eql(301)
        l = 'https://www.google.com:8080/some/branch/url/?var1=val1'
        res.headers['location'].should.eql(l)
        done()


describe 'Multiple parameters', ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  handler = (req, res) ->
    res.write(JSON.stringify(req.params))
    res.end()

  router.get('/<id1>/branch/<int:id2>,<float:id3>/list', handler)
  router.get('/<in(js,css,img):dir>/<path:p>', handler)

  it 'should keep parameter order', (done) ->
    app.request()
      .get('/abc/branch/56,7.7756/list')
      .end (res) ->
        JSON.parse(res.body).should.eql(['abc', 56, 7.7756])
        done()

  it 'should capture parameters in a non-greedy way', (done) ->
    app.request()
      .get('/js/some/path/to/a/javascript/file.js')
      .end (res) ->
        # Before adjusting the internal regexp for ungreedy matching
        # this route would not be executed, since it would try to match
        # 'js/some/path/to/a/javascript' as the first parameter.
        JSON.parse(res.body).should.eql [
          'js'
          'some/path/to/a/javascript/file.js'
        ]
        done()


describe 'Custom parser', ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  router.registerParser 'options', (str) ->
    rv = {}
    options = str.split('/')
    for option in options
      [key, value] = option.split('=')
      rv[key] = value
    return rv

  router.get '/transactions/<options:query>', (req, res) ->
    res.write(JSON.stringify(req.params.query))
    res.end()

  it 'create object containing parsed options', (done) ->
    app.request()
      .get('/transactions/gt=5/lt=10/limit=20')
      .end (res) ->
        JSON.parse(res.body).should.eql
          gt: '5'
          lt: '10'
          limit: '20'
        done()


describe 'Handlers registered on same pattern but by different methods', ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  router.all '/starting/path', (req, res, next) ->
    next('route')

  router.get '/starting/path', (req, res) ->
    res.write('matched!')
    res.end()

  it 'should be treated as separate routes', (done) ->
    app.request()
      .get('/starting/path')
      .end (res) ->
        res.body.should.eql('matched!')
        done()


describe 'Conditional middlewares', ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  router.get '/public/<path:file>', (req, res) ->
    res.write(req.params.file)
    res.end()

  router.all '/private/<path:path>', (req, res, next) ->
    if req.headers['x-user']
      req.loggedIn = true
      return next('route')
    else
      next()

  router.all '/private/<path:path>', (req, res) ->
    res.writeHead(401)
    res.end()

  router.post '/private/addpost/<title>', (req, res) ->
    req.loggedIn.should.eql(true)
    res.write(JSON.stringify(req.params))
    res.end()

  router.get '/private/posts', (req, res) ->
    req.loggedIn.should.eql(true)
    res.write('post list')
    res.end()

  it 'should allow anyone to access public urls', (done) ->
    app.request()
      .get('/public/some/javascript.js')
      .end (res) ->
        res.body.should.eql('some/javascript.js')
        done()

  it 'should allow logged user to access private urls', (done) ->
    app.request()
      .set('X-User', 'user')
      .post('/private/addpost/abc')
      .end (res) ->
        res.body.should.eql('["abc"]') # erases parameters set by middleware routes
        app.request()
          .set('X-User', 'user')
          .get('/private/posts')
          .end (res) ->
            res.body.should.eql('post list')
            done()

  it 'should not allow anonymous user to access private urls', (done) ->
    app.request()
      .post('/private/addpost/abc')
      .end (res) ->
        res.statusCode.should.eql(401)
        app.request()
          .get('/private/posts')
          .end (res) ->
            res.statusCode.should.eql(401)
            done()


describe 'RegExp rule', ->
  router = createRouter()
  app = connect()
  app.use(router.route)

  router.get /^\/regexPath\/([0-9])$/i, (req, res) ->
    res.write(req.params[0])
    res.end()

  it 'should ignore case', (done) ->
    app.request()
      .get('/REGEXPATH/5')
      .end (res) ->
        res.body.should.eql('5')
        done()

  it 'should not route when path doesnt match the pattern', (done) ->
    app.request()
      .get('/REGEXPATH/56')
      .expect(404, done)

