connect = require('connect')

describe 'router.middleware', ->
  router = require('../src/routers')()
  app = connect()
  app.use(router.middleware)

  router.get '/simple/get/pattern', (req, res) ->
    res.write('body1')
    res.end()

  router.post('/simple/no-get/pattern', -> res.end())

  router.del('/simple/no-get/pattern', -> res.end())

  router.get '/pattern/that/uses/many/handlers',
    (req, res, next) -> res.write('part1'); next(),
    (req, res, next) -> res.write('part2'); next()

  router.get '/pattern/that/uses/many/handlers',
    (req, res) -> res.write('part3'); res.end()

  it 'should match simple patterns', (done) ->
    app.request()
      .get('/simple/get/pattern')
      .end (res) ->
        res.body.should.eql('body1')
        done()

  it "should return 405 when pattern doesn't match method", (done) ->
    app.request()
      .get('/simple/no-get/pattern')
      .end (res) ->
        res.statusCode.should.eql(405)
        res.headers['allow'].should.eql('POST, DELETE')
        done()

  it 'should pipe request through all handlers', (done) ->
    app.request()
      .get('/pattern/that/uses/many/handlers')
      .end (res) ->
        res.body.should.eql('part1part2part3')
        done()

