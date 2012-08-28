path = require('path')
url = require('url')


class Compiler
  compile: (patternString) -> new RegExp("^#{patternString}/?$", 'i')


class Router
  constructor: (@compiler) ->
    @methodRoutes =
      GET: []
      POST: []
      PUT: []
      DELETE: []
    @compiled = false

  # Route an incoming request to the appropriate handler chain
  dispatch: (req, res, next) ->
    p = path.normalize(url.parse(req.url).pathname)
    req.path = p
    @compile()
    r = @methodRoutes
    routeArray = r[req.method]
    for route in routeArray
      if match = route.pattern.exec(p)
        req.params = match.slice(1)
        handlerArray = route.handlers
        handle = (i) ->
          if i is handlerArray.length - 1
            n = next
          else
            n = -> process.nextTick(-> handle(i + 1))
          current = handlerArray[i]
          current(req, res, n)
        handle(0)
        return
    # If not routes were matched, check if the route is matched
    # against another http method, if so issue the correct 304 response
    allowed = []
    for own method, routeArray of r
      if method is req.method then continue
      for route in routeArray
        if route.pattern.test(p)
          allowed.push(method)
    if allowed.length
      res.writeHead(405, 'Allow': allowed.join(', '))
      res.end()
      return
    next()

  # Register one of more handler functions to a single route.
  register: (methodName, pattern, handlers...) ->
    routeArray = @methodRoutes[methodName]
    # Only allow routes to be registered before compilation
    if @compiled
      throw new Error('Cannot register routes after first request')
    if not (typeof pattern is 'string' or pattern instanceof RegExp)
      throw new Error('Pattern must be string or regex')
    # Id used to search for existing routes. That way multiple registrations
    # to the same route will append the handler to the same array.
    id = pattern.toString()
    handlerArray = null
    # Check if the route is already registered in this array.
    for route in routeArray
      if route.id is id
        handlerArray = route.handlers
        break
    # If not registered, then create an entry for this route.
    if not handlerArray
      handlerArray = []
      routeArray.push
        id: id
        pattern: pattern
        handlers: handlerArray
    # Register the passed handlers to the handler array associated with
    # this route.
    handlerArray.push(handlers...)

  # Compiles each route to a regular expression
  compile: ->
    if @compiled then return
    for own method, routeArray of @methodRoutes
      for route in routeArray
        if typeof route.pattern isnt 'string'
          continue
        patternString = route.pattern
        if patternString[-1] is '/'
          patternString = patternString.slice(0, patternString.length - 1)
        route.pattern = @compiler.compile(patternString)
    compiled = true


module.exports = () ->
  r = new Router(new Compiler())

  return {
    middleware: (req, res, next) -> r.dispatch(req, res, next)
    get: (pattern, handlers...) -> r.register('GET', pattern, handlers...)
    post: (pattern, handlers...) -> r.register('POST', pattern, handlers...)
    put: (pattern, handlers...) -> r.register('PUT', pattern, handlers...)
    del: (pattern, handlers...) -> r.register('DELETE', pattern, handlers...)
  }
