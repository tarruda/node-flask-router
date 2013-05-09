# The most basic parameter parser, used when no parser is specified. 
# It only ensures that no slashes will be in the string.

module.exports = (str, opts) ->
  if typeof str != 'string' || !str.trim() || str.indexOf('/') != -1
    return null
  return str

