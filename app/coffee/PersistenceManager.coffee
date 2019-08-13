Settings = require "settings-sharelatex"
Errors = require "./Errors"
Metrics = require "./Metrics"
logger = require "logger-sharelatex"
request = (require("requestretry")).defaults({
	maxAttempts: 2
	retryDelay: 10
})

# We have to be quick with HTTP calls because we're holding a lock that
# expires after 30 seconds. We can't let any errors in the rest of the stack
# hold us up, and need to bail out quickly if there is a problem.
MAX_HTTP_REQUEST_LENGTH = 5000 # 5 seconds

module.exports = PersistenceManager =
	getDoc: (project_id, doc_id, _callback = (error, lines, version, ranges, pathname, projectHistoryId) ->) ->
		timer = new Metrics.Timer("persistenceManager.getDoc")
		callback = (args...) ->
			timer.done()
			_callback(args...)

		url = "#{Settings.apis.web.url}/project/#{project_id}/doc/#{doc_id}"
		request {
			url: url
			method: "GET"
			headers:
				"accept": "application/json"
			auth:
				user: Settings.apis.web.user
				pass: Settings.apis.web.pass
				sendImmediately: true
			jar: false
			timeout: MAX_HTTP_REQUEST_LENGTH
		}, (error, res, body) ->
			return callback(error) if error?
			if res.statusCode >= 200 and res.statusCode < 300
				try
					body = JSON.parse body
				catch e
					return callback(e)
				if !body.lines?
					return callback(new Error("web API response had no doc lines"))
				if !body.version? or not body.version instanceof Number
					return callback(new Error("web API response had no valid doc version"))
				if !body.pathname?
					return callback(new Error("web API response had no valid doc pathname"))
				# fix up any broken docs that are already in mongo (overleaf/issues#2162)
				PersistenceManager._fixInvalidLines(body.lines) # modifies body.lines array in-place
				return callback null, body.lines, body.version, body.ranges, body.pathname, body.projectHistoryId
			else if res.statusCode == 404
				return callback(new Errors.NotFoundError("doc not not found: #{url}"))
			else
				return callback(new Error("error accessing web API: #{url} #{res.statusCode}"))

	_fixInvalidLines: (lines) ->
		# trim any unwanted trailing '\r's from stored docs
		matched = for line, i in lines when line.endsWith('\r')
			lines[i] = line.slice(0, -1)
		Metrics.inc 'get-doc.replace-cr' if matched.length > 0

	setDoc: (project_id, doc_id, lines, version, ranges, lastUpdatedAt, lastUpdatedBy,_callback = (error) ->) ->
		timer = new Metrics.Timer("persistenceManager.setDoc")
		callback = (args...) ->
			timer.done()
			_callback(args...)

		url = "#{Settings.apis.web.url}/project/#{project_id}/doc/#{doc_id}"
		request {
			url: url
			method: "POST"
			json:
				lines: lines
				ranges: ranges
				version: version
				lastUpdatedBy: lastUpdatedBy
				lastUpdatedAt: lastUpdatedAt
			auth:
				user: Settings.apis.web.user
				pass: Settings.apis.web.pass
				sendImmediately: true
			jar: false
			timeout: MAX_HTTP_REQUEST_LENGTH
		}, (error, res, body) ->
			return callback(error) if error?
			if res.statusCode >= 200 and res.statusCode < 300
				return callback null
			else if res.statusCode == 404
				return callback(new Errors.NotFoundError("doc not not found: #{url}"))
			else
				return callback(new Error("error accessing web API: #{url} #{res.statusCode}"))

