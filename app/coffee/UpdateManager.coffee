LockManager = require "./LockManager"
RedisManager = require "./RedisManager"
RealTimeRedisManager = require "./RealTimeRedisManager"
ShareJsUpdateManager = require "./ShareJsUpdateManager"
HistoryManager = require "./HistoryManager"
Settings = require('settings-sharelatex')
_ = require("lodash")
async = require("async")
logger = require('logger-sharelatex')
Metrics = require "./Metrics"
Errors = require "./Errors"
DocumentManager = require "./DocumentManager"
RangesManager = require "./RangesManager"
SnapshotManager = require "./SnapshotManager"
Profiler = require "./Profiler"

module.exports = UpdateManager =
	processOutstandingUpdates: (project_id, doc_id, callback = (error) ->) ->
		timer = new Metrics.Timer("updateManager.processOutstandingUpdates")
		UpdateManager.fetchAndApplyUpdates project_id, doc_id, (error) ->
			timer.done()
			return callback(error) if error?
			callback()

	processOutstandingUpdatesWithLock: (project_id, doc_id, callback = (error) ->) ->
		profile = new Profiler("processOutstandingUpdatesWithLock", {project_id, doc_id})
		LockManager.tryLock doc_id, (error, gotLock, lockValue) =>
			return callback(error) if error?
			return callback() if !gotLock
			profile.log("tryLock")
			UpdateManager.processOutstandingUpdates project_id, doc_id, (error) ->
				return UpdateManager._handleErrorInsideLock(doc_id, lockValue, error, callback) if error?
				profile.log("processOutstandingUpdates")
				LockManager.releaseLock doc_id, lockValue, (error) =>
					return callback(error) if error?
					profile.log("releaseLock").end()
					UpdateManager.continueProcessingUpdatesWithLock project_id, doc_id, callback

	continueProcessingUpdatesWithLock: (project_id, doc_id, callback = (error) ->) ->
		RealTimeRedisManager.getUpdatesLength doc_id, (error, length) =>
			return callback(error) if error?
			if length > 0
				UpdateManager.processOutstandingUpdatesWithLock project_id, doc_id, callback
			else
				callback()

	fetchAndApplyUpdates: (project_id, doc_id, callback = (error) ->) ->
		profile = new Profiler("fetchAndApplyUpdates", {project_id, doc_id})
		RealTimeRedisManager.getPendingUpdatesForDoc doc_id, (error, updates) =>
			return callback(error) if error?
			logger.log {project_id: project_id, doc_id: doc_id, count: updates.length}, "processing updates"
			if updates.length == 0
				return callback()
			profile.log("getPendingUpdatesForDoc")
			doUpdate = (update, cb)->
				UpdateManager.applyUpdate project_id, doc_id, update, (err) ->
					profile.log("applyUpdate")
					cb(err)
			finalCallback = (err) ->
				profile.log("async done").end()
				callback(err)
			async.eachSeries updates, doUpdate, finalCallback

	applyUpdate: (project_id, doc_id, update, _callback = (error) ->) ->
		callback = (error) ->
			if error?
				RealTimeRedisManager.sendData {project_id, doc_id, error: error.message || error}
				profile.log("sendData")
			profile.end()
			_callback(error)

		profile = new Profiler("applyUpdate", {project_id, doc_id})
		DocumentManager.getDoc project_id, doc_id, (error, lines, version, ranges, pathname, projectHistoryId) ->
			profile.log("getDoc")
			return callback(error) if error?
			if !lines? or !version?
				return callback(new Errors.NotFoundError("document not found: #{doc_id}"))
			previousVersion = version
			ShareJsUpdateManager.applyUpdate project_id, doc_id, update, lines, version, (error, updatedDocLines, version, appliedOps) ->
				profile.log("sharejs.applyUpdate")
				return callback(error) if error?
				RangesManager.applyUpdate project_id, doc_id, ranges, appliedOps, updatedDocLines, (error, new_ranges, ranges_were_collapsed) ->
					UpdateManager._addProjectHistoryMetadataToOps(appliedOps, pathname, projectHistoryId, lines)
					profile.log("RangesManager.applyUpdate")
					return callback(error) if error?
					RedisManager.updateDocument project_id, doc_id, updatedDocLines, version, appliedOps, new_ranges, update.meta, (error, doc_ops_length, project_ops_length) ->
						profile.log("RedisManager.updateDocument")
						return callback(error) if error?
						HistoryManager.recordAndFlushHistoryOps project_id, doc_id, appliedOps, doc_ops_length, project_ops_length, (error) ->
							profile.log("recordAndFlushHistoryOps")
							return callback(error) if error?
							if ranges_were_collapsed
								logger.log {project_id, doc_id, previousVersion, lines, ranges, update}, "update collapsed some ranges, snapshotting previous content"
								# Do this last, since it's a mongo call, and so potentially longest running
								# If it overruns the lock, it's ok, since all of our redis work is done
								SnapshotManager.recordSnapshot project_id, doc_id, previousVersion, pathname, lines, ranges, (error) ->
									if error?
										logger.error {err: error, project_id, doc_id, version, lines, ranges}, "error recording snapshot"
										return callback(error)
									else
										callback()
							else
								callback()

	lockUpdatesAndDo: (method, project_id, doc_id, args..., callback) ->
		profile = new Profiler("lockUpdatesAndDo", {project_id, doc_id})
		LockManager.getLock doc_id, (error, lockValue) ->
			profile.log("getLock")
			return callback(error) if error?
			UpdateManager.processOutstandingUpdates project_id, doc_id, (error) ->
				return UpdateManager._handleErrorInsideLock(doc_id, lockValue, error, callback) if error?
				profile.log("processOutstandingUpdates")
				method project_id, doc_id, args..., (error, response_args...) ->
					return UpdateManager._handleErrorInsideLock(doc_id, lockValue, error, callback) if error?
					profile.log("method")
					LockManager.releaseLock doc_id, lockValue, (error) ->
						return callback(error) if error?
						profile.log("releaseLock").end()
						callback null, response_args...
						# We held the lock for a while so updates might have queued up
						UpdateManager.continueProcessingUpdatesWithLock project_id, doc_id

	_handleErrorInsideLock: (doc_id, lockValue, original_error, callback = (error) ->) ->
		LockManager.releaseLock doc_id, lockValue, (lock_error) ->
			callback(original_error)

	_addProjectHistoryMetadataToOps: (updates, pathname, projectHistoryId, lines) ->
		doc_length = _.reduce lines,
			(chars, line) -> chars + line.length,
			0
		doc_length += lines.length - 1  # count newline characters
		updates.forEach (update) ->
			update.projectHistoryId = projectHistoryId
			update.meta ||= {}
			update.meta.pathname = pathname
			update.meta.doc_length = doc_length
			# Each update may contain multiple ops, i.e.
			# [{
			# 	ops: [{i: "foo", p: 4}, {d: "bar", p:8}]
			# }, {
			# 	ops: [{d: "baz", p: 40}, {i: "qux", p:8}]
			# }]
			# We want to include the doc_length at the start of each update,
			# before it's ops are applied. However, we need to track any
			# changes to it for the next update.
			for op in update.op
				if op.i?
					doc_length += op.i.length
				if op.d?
					doc_length -= op.d.length
