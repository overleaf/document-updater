sinon = require "sinon"
chai = require("chai")
chai.should()
Settings = require('settings-sharelatex')
rclient_history = require("redis-sharelatex").createClient(Settings.redis.history)
ProjectHistoryKeys = Settings.redis.project_history.key_schema

MockWebApi = require "./helpers/MockWebApi"
DocUpdaterClient = require "./helpers/DocUpdaterClient"

describe "Applying updates to a project's structure", ->
	before ->
		@user_id = 'user-id-123'

	describe "renaming a file", ->
		before (done) ->
			@project_id = DocUpdaterClient.randomId()
			@fileUpdate =
				id: DocUpdaterClient.randomId()
				pathname: '/file-path'
				newPathname: '/new-file-path'
			@fileUpdates = [ @fileUpdate ]
			DocUpdaterClient.sendProjectUpdate @project_id, @user_id, [], @fileUpdates, (error) ->
				throw error if error?
				setTimeout done, 200

		it "should push the applied file renames to the project history changes api", (done) ->
			rclient_history.lrange ProjectHistoryKeys.projectHistoryOps({@project_id}), 0, -1, (error, updates) =>
				throw error if error?

				update = JSON.parse(updates[0])
				update.file.should.equal @fileUpdate.id
				update.pathname.should.equal '/file-path'
				update.new_pathname.should.equal '/new-file-path'
				update.meta.user_id.should.equal @user_id
				update.meta.ts.should.be.a('string')

				done()

	describe "renaming a document", ->
		before ->
			@docUpdate =
				id: DocUpdaterClient.randomId()
				pathname: '/doc-path'
				newPathname: '/new-doc-path'
			@docUpdates = [ @docUpdate ]

		describe "when the document is not loaded", ->
			before (done) ->
				@project_id = DocUpdaterClient.randomId()
				DocUpdaterClient.sendProjectUpdate @project_id, @user_id, @docUpdates, [], (error) ->
					throw error if error?
					setTimeout done, 200

			it "should push the applied doc renames to the project history changes api", (done) ->
				rclient_history.lrange ProjectHistoryKeys.projectHistoryOps({@project_id}), 0, -1, (error, updates) =>
					throw error if error?

					update = JSON.parse(updates[0])
					update.doc.should.equal @docUpdate.id
					update.pathname.should.equal '/doc-path'
					update.new_pathname.should.equal '/new-doc-path'
					update.meta.user_id.should.equal @user_id
					update.meta.ts.should.be.a('string')

					done()

		describe "when the document is loaded", ->
			before (done) ->
				@project_id = DocUpdaterClient.randomId()
				MockWebApi.insertDoc @project_id, @docUpdate.id, {}
				DocUpdaterClient.preloadDoc @project_id, @docUpdate.id, (error) =>
					throw error if error?
					sinon.spy MockWebApi, "getDocument"
					DocUpdaterClient.sendProjectUpdate @project_id, @user_id, @docUpdates, [], (error) ->
						throw error if error?
						setTimeout done, 200

			after ->
				MockWebApi.getDocument.restore()

			it "should update the doc", (done) ->
				DocUpdaterClient.getDoc @project_id, @docUpdate.id, (error, res, doc) =>
					doc.pathname.should.equal @docUpdate.newPathname
					done()

			it "should push the applied doc renames to the project history changes api", (done) ->
				rclient_history.lrange ProjectHistoryKeys.projectHistoryOps({@project_id}), 0, -1, (error, updates) =>
					throw error if error?

					update = JSON.parse(updates[0])
					update.doc.should.equal @docUpdate.id
					update.pathname.should.equal '/doc-path'
					update.new_pathname.should.equal '/new-doc-path'
					update.meta.user_id.should.equal @user_id
					update.meta.ts.should.be.a('string')

					done()