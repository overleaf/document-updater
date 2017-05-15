sinon = require('sinon')
chai = require('chai')
should = chai.should()
modulePath = "../../../../app/js/RealTimeRedisManager.js"
SandboxedModule = require('sandboxed-module')
Errors = require "../../../../app/js/Errors"

describe "RealTimeRedisManager", ->
	beforeEach ->
		@rclient =
			auth: () ->
			exec: sinon.stub()
		@rclient.multi = () => @rclient
		@RealTimeRedisManager = SandboxedModule.require modulePath, requires:
			"redis-sharelatex": createClient: () => @rclient
			"settings-sharelatex":
				redis:
					realtime: @settings =
						key_schema:
							pendingUpdates: ({doc_id}) -> "PendingUpdates:#{doc_id}"
			"logger-sharelatex": { log: () -> }
		@doc_id = "doc-id-123"
		@project_id = "project-id-123"
		@callback = sinon.stub()
	
	describe "getPendingUpdatesForDoc", ->
		beforeEach ->
			@rclient.lpop = sinon.stub()

		describe "successfully", ->
			beforeEach ->
				@update =	{ op: [{ i: "foo", p: 4 }] }
				@jsonUpdate = JSON.stringify @update
				@rclient.lpop = sinon.stub().callsArgWith(1, null, @jsonUpdate)
				@RealTimeRedisManager.getNextPendingUpdateForDoc @doc_id, @callback
			
			it "should pop the next pending update", ->
				@rclient.lpop
					.calledWith("PendingUpdates:#{@doc_id}")
					.should.equal true

			it "should call the callback with the update", ->
				@callback.calledWith(null, @update).should.equal true

		describe "when the JSON doesn't parse", ->
			beforeEach ->
				@jsonUpdate = "broken json"
				@rclient.lpop = sinon.stub().callsArgWith(1, null, @jsonUpdate)
				@RealTimeRedisManager.getNextPendingUpdateForDoc @doc_id, @callback

			it "should return an error to the callback", ->
				@callback.calledWith(new Error("JSON parse error")).should.equal true

	describe "getUpdatesLength", ->
		beforeEach ->
			@rclient.llen = sinon.stub().yields(null, @length = 3)
			@RealTimeRedisManager.getUpdatesLength @doc_id, @callback
		
		it "should look up the length", ->
			@rclient.llen.calledWith("PendingUpdates:#{@doc_id}").should.equal true
		
		it "should return the length", ->
			@callback.calledWith(null, @length).should.equal true
