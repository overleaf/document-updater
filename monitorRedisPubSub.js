const Metrics = require('metrics-sharelatex')
const Redis = require('redis-sharelatex')
const Settings = require('settings-sharelatex')

const clients = new Map()

module.exports = {
  enable: function(per_channel) {
    subscribeTo('applied-ops', per_channel)
    subscribeTo('editor-events', per_channel)
  },
  disable: function() {
    unsubscribeFrom('applied-ops')
    unsubscribeFrom('editor-events')
  }
}

function unsubscribeFrom(key) {
  if (!clients.has(key)) {
    return
  }

  console.warn(`disabling pub/sub monitor for ${key}`)
  const pubsubClient = clients.get(key)
  clients.delete(key)

  pubsubClient.punsubscribe(`${key}:*`)
  pubsubClient.unsubscribe(key)
}

function subscribeTo(key, per_channel) {
  if (clients.has(key)) {
    return
  }

  console.warn(`enabling pub/sub monitor for ${key}`)
  const pubsubClient = Redis.createClient(Settings.redis.pubsub)
  clients.set(key, pubsubClient)

  pubsubClient.psubscribe(`${key}:*`)
  pubsubClient.on('pmessage', (pattern, channel, blob) => {
    processBlob(channel, blob)
  })

  pubsubClient.subscribe(key)
  pubsubClient.on('message', processBlob)

  function processBlob(channel, blob) {
    const opts = {}
    if (per_channel) {
      opts.channel = channel
    }
    Metrics.summary(`redis_pub_sub_${key}`, blob.length, opts)
  }
}
