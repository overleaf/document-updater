/* eslint-disable
    handle-callback-err,
*/
// TODO: This file was created by bulk-decaffeinate.
// Fix any style issues and re-enable lint.
/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * DS205: Consider reworking code to avoid use of IIFEs
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const app = require('../../../../app')
const { waitForDb } = require('../../../../app/js/mongodb')
require('logger-sharelatex').logger.level('fatal')

module.exports = {
  running: false,
  initing: false,
  callbacks: [],
  ensureRunning(callback) {
    if (callback == null) {
      callback = function (error) {}
    }
    if (this.running) {
      return callback()
    } else if (this.initing) {
      return this.callbacks.push(callback)
    }
    this.initing = true
    this.callbacks.push(callback)
    waitForDb().then(() => {
      return app.listen(3003, 'localhost', error => {
        if (error != null) {
          throw error
        }
        this.running = true
        return (() => {
          const result = []
          for (callback of Array.from(this.callbacks)) {
            result.push(callback())
          }
          return result
        })()
      })
    })
  },
}
