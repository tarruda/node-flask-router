path = require('path')
url = require('url')


escapeRegex = (s) -> s.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&')


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


# The most basic parameter parser, which ensures no slashes
# in the string and can optionally validate string length.
defaultParser = (str, opts) ->
  if str.indexOf('/') != -1
    return null
  if opts
    if (isFinite(opts.len) && str.length != opts.len) ||
    (isFinite(opts.min) && str.length < opts.min) ||
    (isFinite(opts.max) && str.length > opts.max)
      return null
  return str


# Extracts parameters out of a request path using a user-supplied regex.
class RegexExtractor
  constructor: (@regex) ->

  extract: (requestPath) ->
    m = @regex.exec(requestPath)
    if ! m then return null
    return m.slice(1)

  test: (requestPath) -> @extract(requestPath) != null


# Extracts parameters out of a request path using a user supplied rule
# with syntax similar to flask routes: http://flask.pocoo.org/.
class RuleExtractor extends RegexExtractor
  constructor: (@parsers) ->
    @regexParts = ['^']
    @params = []

  pushStatic: (staticPart) ->
    @regexParts.push(escapeRegex(staticPart))

  pushParam: (dynamicPart) ->
    @params.push(dynamicPart)
    # Actual parsing/validation is done by the parser function,
    # so a simple non-greedy(since we insert a '$' at the end
    # before compilation) catch-all capture group is inserted.
    @regexParts.push('(.+?)')

  compile: ->
    @regexParts.push('$')
    @regex = new RegExp(@regexParts.join(''))
    return @

  extract: (requestPath) ->
    m = @regex.exec(requestPath)
    if ! m then return null
    params = @params
    parsers = @parsers
    extractedArgs = []
    for i in [1...m.length]
      param = params[i - 1]
      parser = parsers[param.parserName]
      if typeof parser != 'function'
        parser = defaultParser
      value = parser(m[i], param.parserOpts)
      if value == null then return null
      extractedArgs[i - 1] = extractedArgs[param.name] = value
    return extractedArgs
    

# Translates rules into RuleExtractor objects, which internally uses
# regexes and parsers to extract parameters.
class Compiler
  constructor: (parsers) ->
    # Default parsers which take care of parsing/validating arguments.
    @parsers =
      int: (str, opts) ->
        str = str.trim().toLowerCase()
        # Remove leading zeros for comparsion after parsing.
        for i in [0...str.length - 1]
          if str.charAt(i) != '0'
            break
        str = str.slice(i)
        base = 10
        if opts?.base
          base = opts.base
        rv = parseInt(str, base)
        if ! isFinite(rv) || rv.toString(base) != str
          return null
        if opts
          if (isFinite(opts.min) && rv < opts.min) ||
          (isFinite(opts.max) && rv > opts.max)
            return null
        return rv

      float: (str, opts) ->
        str = str.trim()
        rv = parseFloat(str)
        if ! isFinite(rv) || rv.toString() != str
          return null
        if opts
          if (isFinite(opts.min) && rv < opts.min) ||
          (isFinite(opts.max) && rv > opts.max)
            return null
        return rv

      str: (str, opts) -> defaultParser(str, opts)

      path: (str) -> str

      in: (str, opts) ->
        args = opts['*args']
        for i in [0...args.length]
          if args[i].toString() == str then break
        if i < args.length
          return args[i]
        return null
        
    if parsers
      for own k, v of parsers
        @parsers[k] = v

  # Regexes used to parse rules. Based on the regexes found at:
  # https://github.com/mitsuhiko/werkzeug/blob/master/werkzeug/routing.py
  ruleRe:
    ///
    ([^<]+)                         # Static rule section
    |                               # OR        
    (?:<                            # Dynamic rule section:
      (?:                             
        ([a-zA-Z_][a-zA-Z0-9_]*)    # Capture onverter name
          (?:\((.+)\))?             # Capture parser options
        :                           
      )?                            # Parser/opts is optional           
      ([a-zA-Z_][a-zA-Z0-9_]*)      # Capture parameter name
    >)                               
    ///g

  parserOptRe:
    ///
    (?:
        ([a-zA-Z_][a-zA-Z0-9_]*)    # Capture option name
        \s*=\s*                     # Delimiters
    )?
    (?:
      (true|false)                  # Capture boolean literal
      |                             # OR
      (\d+\.\d+|\d+\.|\d+)          # Capture numeric literal OR
      |                             # OR
      (\w+)                         # Capture string literal 
    )\s*,?
    ///g

  parseOpts: (rawOpts) ->
    rv =
      '*args': []
    while match = @parserOptRe.exec(rawOpts)
      name = null
      if match[1]
        name = match[1]
      if match[2] # boolean
        value = Boolean(match[2])
      else if match[3] # number
        value = parseFloat(match[3])
      else # string
        value = match[4]
      if name then rv[name] = value # Named argument
      else rv['*args'].push(value)  # Unamed argument
    return rv

  compile: (pattern) ->
    if pattern instanceof RegExp
      return new RegexExtractor(pattern)
    extractor = new RuleExtractor(@parsers)
    while match = @ruleRe.exec(pattern)
      if match[1]
        # Static section of rule which must be matched literally
        extractor.pushStatic(match[1])
      else
        ruleParam = {}
        if match[2]
          # Parser name
          ruleParam.parserName = match[2]
          if match[3]
            # Parser options
            ruleParam.parserOpts = @parseOpts(match[3])
        # Parameter name
        ruleParam.name = match[4]
        extractor.pushParam(ruleParam)
    return extractor.compile()


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
    urlObj = url.parse(req.url)
    p = path.normalize(urlObj.pathname)
    req.path = p
    @compileRules()
    ruleArray = @rules[req.method]
    for rule in ruleArray
      if extracted = rule.extractor.extract(p)
        req.params = extracted
        end = res.end
        status =
          done = false
        res.end = ->
          status.done = true
          end.call(res)
        handlerChain = rule.handlers
        handle = (i) ->
          if i == handlerChain.length - 1
            n = next
          else
            n = -> process.nextTick(-> handle(i + 1)) if ! status.done
          current = handlerChain[i]
          current(req, res, n)
        handle(0)
        return
    # If no rules were matched, see if appending a slash will result
    # in a match. If so, send a redirect to the correct URL.
    bp = p + '/'
    for rule in ruleArray
      if extracted = rule.extractor.extract(bp)
        res.writeHead(301, 'Location': absoluteUrl(req, bp, urlObj.search))
        res.end()
        return
    # If still no luck, check if the rule is registered
    # with another http method. If it is, issue the correct 405 response
    allowed = [] # Valid methods for this resource
    for own method, ruleArray of @rules
      if method == req.method then continue
      for rule in ruleArray
        if rule.extractor.test(p)
          allowed.push(method)
    if allowed.length
      res.writeHead(405, 'Allow': allowed.join(', '))
      res.end()
      return
    next()

  # Register one of more handler functions to a single route.
  register: (methodName, pattern, handlers...) ->
    ruleArray = @rules[methodName]
    # Only allow rules to be registered before compilation
    if @compiled
      throw new Error('Cannot register rules after compilation')
    if not (typeof pattern == 'string' || pattern instanceof RegExp)
      throw new Error('Pattern must be rule string or regex')
    # Id used to search for existing rules. That way multiple registrations
    # to the same rule will append to the same handler array.
    id = pattern.toString()
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
    handlerArray.push(handlers...)

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
    get: (pattern, handlers...) -> r.register('GET', pattern, handlers...)
    post: (pattern, handlers...) -> r.register('POST', pattern, handlers...)
    put: (pattern, handlers...) -> r.register('PUT', pattern, handlers...)
    del: (pattern, handlers...) -> r.register('DELETE', pattern, handlers...)
    all: (pattern, handlers...) ->
      for method in ['GET', 'POST', 'PUT', 'DELETE']
        r.register(method, pattern, handlers...)
      return
  }
