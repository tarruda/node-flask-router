path = require('path')
url = require('url')


escapeRegex = (s) -> s.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&')

class RegexExtractor
  constructor: (@regex) ->

  extract: (requestPath) ->
    m = @regex.exec(requestPath)
    if !m then return null
    return m.slice(1)

  test: (requestPath) -> @extract(requestPath) != null


class RuleExtractor extends RegexExtractor
  constructor: (@parsers) ->
    @regexParts = ['^']
    @params = []

  pushStatic: (staticPart) ->
    @regexParts.push(escapeRegex(staticPart))

  pushParam: (dynamicPart) ->
    @params.push(dynamicPart)
    # Actual parsing/validation is done by the parser function,
    # so a simple catch-all capture group is inserted
    @regexParts.push('(.+)')

  compile: ->
    @regexParts.push('$')
    @regex = new RegExp(@regexParts.join(''))
    return @

  extract: (requestPath) ->
    m = @regex.exec(requestPath)
    if !m then return null
    params = @params
    parsers = @parsers
    extractedArgs = []
    for i in [1...m.length]
      param = params[i - 1]
      value = parsers[param.parserName](m[i], param.parserOpts)
      if value == null then return null
      extractedArgs[i - 1] = extractedArgs[param.name] = value
    return extractedArgs
    

# Class responsible for transforming user supplied rules into RuleExtractor
# objects, which will be used to extract arguments from the request path.
class Compiler
  constructor: (parsers) ->
    # Default parsers which take care of parsing/validating arguments.
    @parsers =
      int: (str, opts) ->
        str = str.trim()
        base = 10
        if opts?.base
          base = opts.base
        rv = parseInt(str, base)
        if !isFinite(rv) || rv.toString(base) != str
          return null
        if opts
          if (isFinite(opts.min) && rv < min) ||
          (isFinite(opts.max) && rv > max)
            return null
        return rv

      float: (str, opts) ->
        str = str.trim()
        rv = parseFloat(str)
        if !isFinite(rv) || rv.toString() != str
          return null
        if opts
          if (isFinite(opts.min) && rv < min) ||
          (isFinite(opts.max) && rv > max)
            return null
        return rv

      # Doesn't accept slashes
      str: (str, opts) ->
        if str.indexOf('/') != -1
          return null
        if opts
          if (isFinite(opts.len) && rv.length != opts.len) ||
          (isFinite(opts.minlen) && rv.length < opts.minlen) ||
          (isFinite(opts.maxlen) && rv.length > opts.maxlen)
            return null
        return str

      path: (str) -> str
    if parsers
      for own k, v in parsers
        @parsers[k] = v

  # Regexes used to parse user-supplied rules with syntax similar to Flask
  # (python web framework).
  # Based on the regexes found at
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
    ([a-zA-Z_][a-zA-Z0-9_]*)        # Capture option name
    \s*=\s*                         # Delimiters
    (?:
      (true|false)                  # Capture boolean literal
      |                             # OR
      (\d+\.\d+|\d+\.|\d+)          # Capture numeric literal OR
      |                             # OR
      (\w+)                         # Capture string literal 
    )\s*,?
    ///g

  parseOpts: (rawOpts) ->
    rv = {}
    while match = @parserOptRe.exec(rawArgs)
      name = match[1]
      if match[2] # boolean
        rv[name] = Boolean(match[2])
      else if match[3] # number
        rv[name] = parseFloat(match[3])
      else # string
        rv[name] = match[4]
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
            ruleParam.parserOptions = @parseOpts(match[3])
        # Parameter name
        ruleParam.name = match[4]
        extractor.pushParam(ruleParam)
    return extractor.compile()


class Router
  constructor: (@compiler) ->
    @rules =
      GET: []
      POST: []
      PUT: []
      DELETE: []
    @compiled = false

  # Route an incoming request to the appropriate handlers based on matched
  # rules.
  dispatch: (req, res, next) ->
    p = path.normalize(url.parse(req.url).pathname)
    req.path = p
    @compileRules()
    ruleArray = @rules[req.method]
    for route in ruleArray
      if extracted = route.extractor.extract(p)
        req.params = extracted
        handlerChain = route.handlers
        handle = (i) ->
          if i == handlerChain.length - 1
            n = next
          else
            n = -> process.nextTick(-> handle(i + 1))
          current = handlerChain[i]
          current(req, res, n)
        handle(0)
        return
    # If no rules were matched, check if the rule is registered
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
  if not compiler then compiler = new Compiler()
  r = new Router(compiler)

  return {
    middleware: (req, res, next) -> r.dispatch(req, res, next)
    get: (pattern, handlers...) -> r.register('GET', pattern, handlers...)
    post: (pattern, handlers...) -> r.register('POST', pattern, handlers...)
    put: (pattern, handlers...) -> r.register('PUT', pattern, handlers...)
    del: (pattern, handlers...) -> r.register('DELETE', pattern, handlers...)
    all: (pattern, handlers...) ->
      for method in ['GET', 'POST', 'PUT', 'DELETE']
        r.register(method, pattern, handlers...)
      return
  }
