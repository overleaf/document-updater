metrics = require('./Metrics')
Settings = require('settings-sharelatex')
redis = require("redis-sharelatex")
rclient = redis.createClient(Settings.redis.lock)
keys = Settings.redis.lock.key_schema
logger = require "logger-sharelatex"
os = require "os"
crypto = require "crypto"

HOST = os.hostname()
PID = process.pid
RND = crypto.randomBytes(4).toString('hex')
COUNT = 0

module.exports = LockManager =
	LOCK_TEST_INTERVAL: 50 # 50ms between each test of the lock
	MAX_TEST_INTERVAL: 1000 # back off to 1s between each test of the lock
	MAX_LOCK_WAIT_TIME: 10000 # 10s maximum time to spend trying to get the lock
	LOCK_TTL: 30 # seconds. Time until lock auto expires in redis.
	EXTEND_DELAY: 1000 # only extend the lock if it is more than 1s old

	# Use a signed lock value as described in
	# http://redis.io/topics/distlock#correct-implementation-with-a-single-instance
	# to prevent accidental unlocking by multiple processes
	randomLock : (key) ->
		time = Date.now()
		lockValue = {
			key: key
			creationTime: time
			expiryTime: time + LockManager.LOCK_TTL*1000
			lastModifiedTime: time
			uid:"locked:host=#{HOST}:pid=#{PID}:random=#{RND}:time=#{time}:count=#{COUNT++}"
		}
		return lockValue

	unlockScript: 'if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("del", KEYS[1]) else return 0 end';
	extendScript: 'if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("expire", KEYS[1], ARGV[2]) else return 0 end';

	tryLock : (doc_id, callback = (err, isFree)->)->
		key = keys.blockingKey(doc_id:doc_id)
		lockValue = LockManager.randomLock(key)
		rclient.set key, lockValue.uid, "EX", @LOCK_TTL, "NX", (err, gotLock)->
			return callback(err) if err?
			if gotLock == "OK"
				metrics.inc "doc-not-blocking"
				callback err, true, lockValue
			else
				metrics.inc "doc-blocking"
				logger.log {doc_id}, "doc is locked"
				callback err, false

	getLock: (doc_id, callback = (error, lockValue) ->) ->
		startTime = Date.now()
		testInterval = LockManager.LOCK_TEST_INTERVAL
		do attempt = () ->
			if Date.now() - startTime > LockManager.MAX_LOCK_WAIT_TIME
				e = new Error("Timeout")
				e.doc_id = doc_id
				return callback(e)

			LockManager.tryLock doc_id, (error, gotLock, lockValue) ->
				return callback(error) if error?
				if gotLock
					callback(null, lockValue)
				else
					setTimeout attempt, testInterval
					# back off when the lock is taken to avoid overloading
					testInterval = Math.min(testInterval * 2, LockManager.MAX_TEST_INTERVAL)

	checkLock: (doc_id, callback = (err, isFree)->)->
		key = keys.blockingKey(doc_id:doc_id)
		rclient.exists key, (err, exists) ->
			return callback(err) if err?
			exists = parseInt exists
			if exists == 1
				metrics.inc "doc-blocking"
				callback err, false
			else
				metrics.inc "doc-not-blocking"
				callback err, true

	extendLock: (lockValue, callback) ->
		now = Date.now()
		timeSinceLastCheck = now - lockValue.lastModifiedTime
		if timeSinceLastCheck > LockManager.EXTEND_DELAY
			lockValue.lastModifiedTime = now # don't check again for another second
			rclient.eval LockManager.extendScript, 1, lockValue.key, lockValue.uid, @LOCK_TTL, (err, result) ->
				return callback(err) if err?
				if result is 1
					lockValue.expiryTime = now + (LockManager.LOCK_TTL * 1000)
					callback() ## extended lock ok
				else
					# failed to extend the lock
					callback(new Error("failed to extend the lock"))
		else
			callback()

	releaseLock: (doc_id, lockValue, callback)->
		key = keys.blockingKey(doc_id:doc_id)
		rclient.eval LockManager.unlockScript, 1, key, lockValue.uid, (err, result) ->
			if err?
				return callback(err)
			if result? and result isnt 1 # successful unlock should release exactly one key
				logger.error {doc_id:doc_id, lockValue:lockValue.uid, redis_err:err, redis_result:result}, "unlocking error"
				return callback(new Error("tried to release timed out lock"))
			callback(err,result)
