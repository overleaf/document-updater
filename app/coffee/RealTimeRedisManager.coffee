Settings = require('settings-sharelatex')
rclient = require("redis-sharelatex").createClient(Settings.redis.realtime)
Keys = Settings.redis.realtime.key_schema
logger = require('logger-sharelatex')

module.exports = RealTimeRedisManager =
	getNextPendingUpdateForDoc : (doc_id, callback)->
		rclient.lpop Keys.pendingUpdates({doc_id}), (error, reply) ->
			return callback(error) if error?
			return callback() if not reply?
			jsonUpdate = reply
			try
				update = JSON.parse jsonUpdate
			catch e
				return callback e
			callback error, update

	getUpdatesLength: (doc_id, callback)->
		rclient.llen Keys.pendingUpdates({doc_id}), callback

	sendData: (data) ->
		rclient.publish "applied-ops", JSON.stringify(data)
