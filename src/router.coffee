
Compiler = require('./compiler')

url = require('url')

absoluteUrl = (req, pathname, search) ->
  protocol = 'http'
  if req.headers['x-protocol'] == 'https'
    protocol = 'https'
  rv = [protocol, '://', req.headers.host]
  if port = req.headers['x-port']
    rv.push(":#{port}")
  rv.push(pathname)
  if search
    rv.push(search)
  return rv.join('')


normalizePathname = (pathname) ->
  rv = pathname.replace(/\/\.\//g, '/')
  while match = /\/[^/][^/]*\/\.\./.exec(rv)
    rv = rv.replace(match[0], '')
  rv = rv.replace(/\/\.\./g, '')
  rv = rv.replace(/\.\//g, '')
  return rv || '/'


# Encapsulates the routing logic. It depends on the compiler object,
# which will transform rules in 'extractors', objects that contain
# two methods: 'test' and 'extract' used in the routing process.
class Router
  constructor: (@compiler) ->
    @rules =
      GET: []
      POST: []
      PUT: []
      DELETE: []
      PATCH: []
    @compiled = false


  # Route an incoming request to the appropriate handlers based on matched
  # rules or regexes.
  route: (req, res, next) ->
    if typeof next != 'function'
      next = (err) ->
        status = 404
        if err?.status then status = err.status
        res.writeHead(status)
        res.end()
    
    # support usePath
    req.usePath = req.originalUrl
      .substr(0, req.originalUrl.length
        - req.url.length)

    # support an extended res.send
    #res.send = (code, headers, data) ->
    #  args = send.arguments(code, headers, data)
    #  res.writeHead(args.code, args.headers)
    #  if (null != args.data)
    #    res.write(args.data)
    #  @end()


    urlObj = url.parse(req.url)
    p = normalizePathname(urlObj.pathname)
    req.path = p
    @compileRules()
    ruleArray = @rules[req.method]
    matchedRules = {}

    checkRule = (idx) ->
      if idx == ruleArray.length then return fail();
      rule = ruleArray[idx]
      if extracted = rule.extractor.extract(p)
        matchedRules[rule.id] = 1
        req.params = extracted
        end = res.end
        status =
          done: false
        res.end = (args...) ->
          status.done = true
          end.apply(res, args)
        handlerChain = rule.handlers
        handle = (i) ->
          n = (arg) ->
            if status.done then return
            if arg == 'route'
              return checkRule(idx + 1)
            if i == handlerChain.length - 1 then res.end()
            else handle(i + 1)
          current = handlerChain[i]
          current(req, res, n)
        handle(0)
      else
        checkRule(idx + 1)
    fail = =>
      # If no rules were matched, see if appending a slash will result
      # in a match. If so, send a redirect to the correct URL.
      bp = p + '/'
      for rule in ruleArray
        if extracted = rule.extractor.extract(bp)
          # ignore if the rule already matched on a pipeline
          if rule.id of matchedRules
            continue
          res.writeHead(301, 'Location': absoluteUrl(req, bp, urlObj.search))
          res.end()
          return
      # If still no luck, check if the rule is registered
      # with another http method. If it is, send a 405 status code
      allowed = [] # Valid methods for this resource
      for own method, ruleArray of @rules
        if method == req.method then continue
        for rule in ruleArray
          if rule.extractor.test(p)
            # ignore if the rule already matched on a pipeline
            if rule.id of matchedRules
              continue
            allowed.push(method)
            break
      if allowed.length
        res.writeHead(405, 'Allow': allowed.join(', '))
        res.end()
        return
      next()

    checkRule(0)

  # Register one of more handler functions to a single route.
  register: (prefix, methodName, pattern, handlers...) ->
    ruleArray = @rules[methodName]
    # Only allow rules to be registered before compilation
    if @compiled
      throw new Error('Cannot register rules after compilation')
    if not (typeof pattern == 'string' || pattern instanceof RegExp)
      throw new Error('Pattern must be rule string or regex')
    # Id used to search for existing rules. That way multiple registrations
    # to the same rule will append to the same handler array.
    #
    # The prefix is basically the router method used to register the handler,
    # so possible prefixes are: 'get', 'post', 'put', 'del' and 'all'.
    #
    # This means that while two handlers may be registered to the same
    # pattern, they will be appended to different rules if the method
    # used to register them is different. 
    #
    # For example, consider a GET request to /starting/path:
    #
    # router.all '/starting/path', (req, res, next) ->
    #   # check some condition then
    #   next('route')
    #
    # router.get '/starting/path', (req, res) ->
    #   # handle request
    #
    # In this above example, next('route') on the first handler
    # will invoke the other handler even though they use the same
    # url pattern.
    id = "#{prefix}##{pattern.toString()}"
    handlerArray = null
    # Check if the rule is already registered in this array.
    for rule in ruleArray
      if rule.id == id
        handlerArray = rule.handlers
        break
    # If not registered, then create an entry for this rule.
    if not handlerArray
      handlerArray = []
      ruleArray.push
        id: id
        pattern: pattern
        handlers: handlerArray
    # Register the passed handlers to the handler array associated with
    # this rule.
    for handler in handlers
      if typeof handler == 'function'
        handlerArray.push(handler)
      else if Array.isArray(handler)
        @register.apply(@, [prefix, methodName, pattern].concat(handler))
      else
        throw new Error('Handler must be a function or array of functions')
    return handlers

  # Compiles all rules
  compileRules: ->
    if @compiled then return
    for own method, ruleArray of @rules
      for rule in ruleArray
        rule.extractor = @compiler.compile(rule.pattern)
    compiled = true


module.exports = (parsers) ->
  if not compiler then compiler = new Compiler(parsers)
  r = new Router(compiler)

  return {
    route: (req, res, next) -> r.route(req, res, next)
    registerParser: (name, parser) -> compiler.parsers[name] = parser
    get: (pattern, handlers...) ->
      r.register('get', 'GET', pattern, handlers...)
    post: (pattern, handlers...) ->
      r.register('post', 'POST', pattern, handlers...)
    put: (pattern, handlers...) ->
      r.register('put', 'PUT', pattern, handlers...)
    del: (pattern, handlers...) ->
      r.register('del', 'DELETE', pattern, handlers...)
    patch: (pattern, handlers...) ->
      r.register('patch', 'PATCH', pattern, handlers...)
    all: (pattern, handlers...) ->
      for method in ['GET', 'POST', 'PUT', 'DELETE', 'PATCH']
        r.register('all', method, pattern, handlers...)
      return handlers
    use: (usepath, handlers...) ->
      if (!handlers.length) 
        handlers = [usepath]
        usepath = '/'
      if (usepath.slice(-1) != '/')
        usepath += '/'
      handlers.unshift (req, res, next) ->
        req.url = '/' + req.params.__path
        next()
      @all("#{usepath}<path:__path>", handlers...)
      return handlers
  }
