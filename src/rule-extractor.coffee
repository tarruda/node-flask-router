RegexExtractor = require('./regex-extractor')
defaultParser = require('./default-parser')

escapeRegex = (s) -> s.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&')

# Extracts parameters out of a request path using a user-supplied regex.
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
    @regexParts.push('(.*?)')

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
    
module.exports = RuleExtractor

