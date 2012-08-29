connect = require('connect')
createRouter = require('../src/router')

describe 'Static rule matching', ->
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

  it 'should match simple patterns', (done) ->
    app.request()
      .get('/$imple/.get/pattern$')
      .end (res) ->
        res.body.should.eql('body1')
        done()

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
