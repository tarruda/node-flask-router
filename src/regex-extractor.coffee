class RegexExtractor
  constructor: (@regex) ->

  extract: (requestPath) ->
    m = @regex.exec(requestPath)
    if ! m then return null
    return m.slice(1)

  test: (requestPath) -> @extract(requestPath) != null

module.exports = RegexExtractor

