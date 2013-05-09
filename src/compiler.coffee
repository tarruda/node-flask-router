# Translates rules into RuleExtractor objects, which internally uses
# regexes and parsers to extract parameters.

RuleExtractor = require('./rule-extractor')
RegexExtractor = require('./regex-extractor')
defaultParser = require('./default-parser')

class Compiler
  constructor: (parsers) ->
    # Default parsers which take care of parsing/validating arguments.
    @parsers =
      int: (str, opts) ->
        if typeof str != 'string' || str.trim() == ''
          return null
        base = 10
        pattern = /^[0-9]+$/
        if opts?.base == 2
          base = 2
          pattern = /^[0-1]+$/
        if opts?.base == 8
          base = 8
          pattern = /^[0-7]+$/
        else if opts?.base == 16
          base = 16
          pattern = /^[0-9a-fA-F]+$/
        if ! pattern.test(str) then return null
        rv = parseInt(str, base)
        if opts
          if (isFinite(opts.min) && rv < opts.min) ||
          (isFinite(opts.max) && rv > opts.max)
            return null
        return rv

      float: (str, opts) ->
        if typeof str != 'string' || str.trim() == '' || isNaN(str)
          return null
        rv = parseFloat(str)
        if opts
          if (isFinite(opts.min) && rv < opts.min) ||
          (isFinite(opts.max) && rv > opts.max)
            return null
        return rv

      str: (str, opts) ->
        if defaultParser(str) == null then return null
        if opts
          if (isFinite(opts.len) && str.length != opts.len) ||
          (isFinite(opts.min) && str.length < opts.min) ||
          (isFinite(opts.max) && str.length > opts.max)
            return null
        return str

      path: (str, opts) ->
        if str || opts.optional
          return str
        return null

      in: (str, opts) ->
        args = opts['*args']
        for i in [0...args.length]
          if args[i].toString() == str then break
        if i < args.length
          return args[i]
        return null

      uuid: (str) ->
        if /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(str)
          return str.toLowerCase()
        return null
        
    if parsers
      for own k, v of parsers
        @parsers[k] = v

  # Regexes used to parse rules. Based on the regexes found at:
  # https://github.com/mitsuhiko/werkzeug/blob/master/werkzeug/routing.py
  ruleRe:
    ///
    ([^<]+)                           # Static rule section
    |                                 # OR        
    (?:<                              # Dynamic rule section:
      (?:                               
        ([a-zA-Z_][a-zA-Z0-9_]*)      # Capture onverter name
          (?:\((.+)\))?               # Capture parser options
        :                             
      )?                              # Parser/opts is optional
      ([a-zA-Z_][a-zA-Z0-9_]*)        # Capture parameter name
    >)                                 
    ///g

  parserOptRe:
    ///
    (?:
        ([a-zA-Z_][a-zA-Z0-9_]*)      # Capture option name
        \s*=\s*                       # Delimiters
    )?
    (?:
      (true|false)                    # Capture boolean literal
      |                               # OR
      (\d+\.\d+|\d+\.|\d+)            # Capture numeric literal OR
      |                               # OR
      (\w+)                           # Capture string literal 
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

module.exports = Compiler

