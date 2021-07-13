/* eslint-disable
    camelcase,
    no-return-assign,
    no-unused-vars,
*/
// TODO: This file was created by bulk-decaffeinate.
// Fix any style issues and re-enable lint.
/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * DS206: Consider reworking classes to avoid initClass
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const sinon = require('sinon')
const modulePath = '../../../../app/js/ProjectManager.js'
const SandboxedModule = require('sandboxed-module')

describe('ProjectManager - flushAndDeleteProject', function () {
  beforeEach(function () {
    let Timer
    this.ProjectManager = SandboxedModule.require(modulePath, {
      requires: {
        './RedisManager': (this.RedisManager = {}),
        './ProjectHistoryRedisManager': (this.ProjectHistoryRedisManager = {}),
        './DocumentManager': (this.DocumentManager = {}),
        './HistoryManager': (this.HistoryManager = {
          flushProjectChanges: sinon.stub().callsArg(2),
        }),
        './Metrics': (this.Metrics = {
          Timer: (Timer = (function () {
            Timer = class Timer {
              static initClass() {
                this.prototype.done = sinon.stub()
              }
            }
            Timer.initClass()
            return Timer
          })()),
        }),
      },
    })
    this.project_id = 'project-id-123'
    return (this.callback = sinon.stub())
  })

  describe('successfully', function () {
    beforeEach(function (done) {
      this.doc_ids = ['doc-id-1', 'doc-id-2', 'doc-id-3']
      this.RedisManager.getDocIdsInProject = sinon
        .stub()
        .callsArgWith(1, null, this.doc_ids)
      this.DocumentManager.flushAndDeleteDocWithLock = sinon.stub().callsArg(3)
      return this.ProjectManager.flushAndDeleteProjectWithLocks(
        this.project_id,
        {},
        error => {
          this.callback(error)
          return done()
        }
      )
    })

    it('should get the doc ids in the project', function () {
      return this.RedisManager.getDocIdsInProject
        .calledWith(this.project_id)
        .should.equal(true)
    })

    it('should delete each doc in the project', function () {
      return Array.from(this.doc_ids).map(doc_id =>
        this.DocumentManager.flushAndDeleteDocWithLock
          .calledWith(this.project_id, doc_id, {})
          .should.equal(true)
      )
    })

    it('should flush project history', function () {
      return this.HistoryManager.flushProjectChanges
        .calledWith(this.project_id, {})
        .should.equal(true)
    })

    it('should call the callback without error', function () {
      return this.callback.calledWith(null).should.equal(true)
    })

    return it('should time the execution', function () {
      return this.Metrics.Timer.prototype.done.called.should.equal(true)
    })
  })

  return describe('when a doc errors', function () {
    beforeEach(function (done) {
      this.doc_ids = ['doc-id-1', 'doc-id-2', 'doc-id-3']
      this.RedisManager.getDocIdsInProject = sinon
        .stub()
        .callsArgWith(1, null, this.doc_ids)
      this.DocumentManager.flushAndDeleteDocWithLock = sinon.spy(
        (project_id, doc_id, options, callback) => {
          if (doc_id === 'doc-id-1') {
            return callback(
              (this.error = new Error('oops, something went wrong'))
            )
          } else {
            return callback()
          }
        }
      )
      return this.ProjectManager.flushAndDeleteProjectWithLocks(
        this.project_id,
        {},
        error => {
          this.callback(error)
          return done()
        }
      )
    })

    it('should still flush each doc in the project', function () {
      return Array.from(this.doc_ids).map(doc_id =>
        this.DocumentManager.flushAndDeleteDocWithLock
          .calledWith(this.project_id, doc_id, {})
          .should.equal(true)
      )
    })

    it('should still flush project history', function () {
      return this.HistoryManager.flushProjectChanges
        .calledWith(this.project_id, {})
        .should.equal(true)
    })

    it('should record the error', function () {
      return this.logger.error
        .calledWith(
          { err: this.error, projectId: this.project_id, docId: 'doc-id-1' },
          'error deleting doc'
        )
        .should.equal(true)
    })

    it('should call the callback with an error', function () {
      return this.callback
        .calledWith(sinon.match.instanceOf(Error))
        .should.equal(true)
    })

    return it('should time the execution', function () {
      return this.Metrics.Timer.prototype.done.called.should.equal(true)
    })
  })
})
