
exports.arguments = (code, headers, data) ->
  # .send(data), .send(code) or .send(code, data)
  if (!data?)
    data = headers
    headers = {}
  # .send(data)
  if (null == data && typeof(code) != 'number')
    data = code
    code = 200
  if (typeof(data) == 'string') 
    ctype = 'text/html; charset=utf-8'
  else if (data instanceof Error) 
    code = data.code || 500
    ctype = 'application/json'
    ans = {message: data.message}
    if (process.env['NODE_ENV'] == 'development')
      ans.stack = data.stack
    data = JSON.stringify(ans)
  else if (null != data && !(data instanceof Buffer))
    ctype = 'application/json'
    data = JSON.stringify(data)
    
  if (ctype && !headers['content-type'])
    headers['content-type'] = ctype

  return {code: code, headers: headers, data: data}

