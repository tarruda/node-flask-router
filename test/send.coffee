a = require('../src/send').arguments

checks = (desc, o1, o2) ->
  return (done) ->
    for key of o2
      o2[key].should.eql o1[key]
    done()

describe 'arguments(some arguments)', ->

  it 'accepts just code',
    checks a(100), {
      code: 100
    }

  it 'accepts code and json',
    checks a(404, {err: null}), {
      code: 404,
      data: JSON.stringify({err:null})
    }

  it 'accepts code header json',
    checks a(302, {location: 'http://google.com'}, {err: null}), {
      code: 302,
      headers:{
        'content-type': 'application/json',
        location:'http://google.com'
      },
      data: JSON.stringify({err:null})
    }

  it 'accepts just json',
    checks a({done: true}), {
      code: 200,
      data: JSON.stringify({done:true})
    }

  it 'accepts just buffer',
    checks a(new Buffer('hello')), {
      code: 200,
      headers: {}
    }

  it 'accepts just error',
    checks a(new Error('Message')), {
      code: 500,
      data: JSON.stringify({message: 'Message'})
    }
