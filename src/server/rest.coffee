# A REST-ful frontend to the OT server.
#
# See the docs for details and examples about how the protocol works.

http = require 'http'
url  = require 'url'
iframe = require './iframe'

nameregexes = {}
accessControlAllowOrigin = null

send403 = (res, message = 'Forbidden\n') ->
  res.writeHead 403, {'Content-Type': 'text/plain'}
  res.end message

send404 = (res, message = '404: Your document could not be found.\n') ->
  res.writeHead 404, {'Content-Type': 'text/plain'}
  res.end message

sendError = (res, message, head = false) ->
  if message == 'forbidden'
    if head
      send403 res, ""
    else
      send403 res
  else if message == 'Document does not exist'
    if head
      send404 res, ""
    else
      send404 res
  else
    console.warn "REST server does not know how to send error: '#{message}'"
    if head
      res.writeHead 500, {'Content-Type': 'text/plain'}
      res.end "Error: #{message}\n"
    else
      res.writeHead 500, {}
      res.end ""

send400 = (res, message) ->
  res.writeHead 400, {'Content-Type': 'text/plain'}
  res.end message

send200 = (req, res, message = "OK\n", contentType = "text/plain") ->
  headers = {'Content-Type': contentType}
  if accessControlAllowOrigin == '*'
    headers['Access-Control-Allow-Origin'] = req.headers.origin
  else
    headers['Access-Control-Allow-Origin'] = accessControlAllowOrigin if accessControlAllowOrigin != null
  res.writeHead 200, headers
  res.end message

sendJSON = (res, obj) ->
  headers = {'Content-Type': 'application/json'}
  headers['Access-Control-Allow-Origin'] = accessControlAllowOrigin if accessControlAllowOrigin != null
  res.writeHead 200, headers
  res.end JSON.stringify(obj) + '\n'

# Callback is only called if the object was indeed JSON
expectJSONObject = (req, res, callback) ->
  pump req, (data) ->
    try
      obj = JSON.parse data
    catch error
      send400 res, 'Supplied JSON invalid'
      return

    callback(obj)

pump = (req, callback) ->
  data = ''
  req.on 'data', (chunk) -> data += chunk
  req.on 'end', () -> callback(data)

# prepare data for createClient. If createClient success, then we pass client
# together with req and res into the callback. Otherwise, stop the flow right
# here and send error back
#
# req - instance of 'http.ServerRequest'
# res - instance of 'http.ClientRequest'
# createClient - create a sharejs client
# cb - callback which accept req, res, client in that order
auth = (req, res, createClient, cb) ->
  data =
    headers: req.headers
    remoteAddress: req.connection.remoteAddress
    authentication: req.params.urlparts.query.authentication
    url: req.originalUrl
    method: req.method

  createClient data, (error, client) ->
    if client
      cb? req, res, client
    else
      sendError res, error

# GET returns the document snapshot. The version and type are sent as headers.
# I'm not sure what to do with document metadata - it is inaccessable for now.
getDocument = (req, res, client) ->
  client.getSnapshot req.params.name, (error, doc) ->
    if doc
      res.setHeader 'X-OT-Type', doc.type.name
      res.setHeader 'X-OT-Version', doc.v
      if req.method == "HEAD"
        send200 req, res, ""
      else
        if typeof doc.snapshot == 'string'
          send200 req, res, doc.snapshot
        else
          sendJSON req, res, doc.snapshot
    else
      if req.method == "HEAD"
        sendError res, error, true
      else
        sendError res, error

getOperations = (req, res, client) ->
  client.getOps req.params.name, 0, null, (error, ops) ->
    send200 req, res, JSON.stringify ops

getIframe = (req, res, client) ->
    send200 req, res, iframe.content, 'text/html'
  
# Put is used to create a document. The contents are a JSON object with {type:TYPENAME, meta:{...}}
putDocument = (req, res, client) ->
  expectJSONObject req, res, (obj) ->
      type = obj?.type
      meta = obj?.meta

      unless typeof type == 'string' and (meta == undefined or typeof meta == 'object')
        send400 res, 'Type invalid'
      else
        client.create req.params.name, type, meta, (error) ->
          if error
            sendError res, error
          else
            send200 req, res

# POST submits an op to the document.
postDocument = (req, res, client) ->
  query = url.parse(req.url, true).query

  version = if query?.v?
    parseInt query?.v
  else
    parseInt req.headers['x-ot-version']

  unless version? and version >= 0
    send400 res, 'Version required - attach query parameter ?v=X on your URL or set the X-OT-Version header'
  else
    expectJSONObject req, res, (obj) ->
      opData = {v:version, op:obj, meta:{source:req.socket.remoteAddress}}
      client.submitOp req.params.name, opData, (error, newVersion) ->
        if error?
          sendError res, error
        else
          sendJSON res, {v:newVersion}

# DELETE a document
deleteDocument = (req, res, client) ->
  client.delete req.params.name, (error) ->
    if error
      sendError res, error
    else
      send200 req, res

routes = [
  {method: 'GET',    pattern: new RegExp("^/doc/(?:([^/]+?))/?$"),            func: getDocument},
  {method: 'HEAD',   pattern: new RegExp("^/doc/(?:([^/]+?))/?$"),            func: getDocument},
  {method: 'PUT',    pattern: new RegExp("^/doc/(?:([^/]+?))/?$"),            func: putDocument},
  {method: 'POST',   pattern: new RegExp("^/doc/(?:([^/]+?))/?$"),            func: postDocument},
  {method: 'DELETE', pattern: new RegExp("^/doc/(?:([^/]+?))/?$"),            func: deleteDocument},
  {method: 'GET',    pattern: new RegExp("^/doc/(?:([^/]+?))/operations/?$"), func: getOperations},
  {method: 'GET',    pattern: new RegExp("^/iframe/$"),                       func: getIframe}
]

# create a http request handler that is capable of routing request to the
# correct functions
# After getting the document name, `req` will have params which contain name of
# the document
makeDispatchHandler = (createClient, options) ->
  (req, res, next) ->
    urlParts = url.parse req.url, true
    urlBase  = options.base
    pathname = urlParts.pathname.replace options.base, ""
    if options.accessControlAllowOrigin?
        accessControlAllowOrigin = options.accessControlAllowOrigin
    else 
        accessControlAllowOrigin = null
    matched = false
    for route in routes
      if req.method == route.method and match = pathname.match route.pattern
        req.params or= {}
        req.params.name = match[1]
        req.params.urlparts = urlParts
        auth req, res, createClient, route.func
        matched = true
    if not matched
      next()

module.exports = makeDispatchHandler
