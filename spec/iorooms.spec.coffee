Browser = require 'zombie'
expect  = require 'expect.js'
_       = require 'underscore'

waitFor = (callback) ->
  # Try to execute the callback periodically until it returns truthy.  Make
  # sure the callback is idempotent.
  interval = setInterval ->
    if callback()
      clearInterval(interval)
  , 10

describe "iorooms", ->
  before ->
    @server = require('../testserver').start()
  after ->
    @server.app.close()

  it "connects and disconnects", (done) ->
    @browser3 = new Browser()
    @browser3.visit "http://localhost:3000"
    waitFor =>
      socketIDs = (socketID for socketID, socket of @server.io.roomClients)
      if socketIDs.length == 1
        @browser3.window.close()
        @server.app.close()
        @server = require('../testserver').start()
        done()
        return true

  it "connects to the socket", (done) ->
    @browser = new Browser()
    @browser2 = new Browser()
    @browser.visit "http://localhost:3000", ->
    @browser2.visit "http://localhost:3000", ->

    waitFor =>
      socketIDs = (socketID for socketID, socket of @server.io.roomClients)
      if socketIDs.length == 2
        done()
        return true

  it "connects to a room", (done) ->
    @browser.fill("#room", "room")
    @browser2.fill("#room", "room")

    @browser.pressButton("#joinRoom")
    @browser2.pressButton("#joinRoom")

    waitFor =>
      room = @server.io.rooms["/iorooms/room"]
      joined = 0
      browsers = [@browser, @browser2]
      for browser in browsers
        socketID = browser.evaluate("socket.socket.sessionid")
        if _.contains room, socketID
          joined += 1

      if joined == browsers.length
        expect(@server.iorooms.roomSessions["room"].length).to.eql(2)
        for sid in @server.iorooms.roomSessions["room"]
          expect(@server.iorooms.sessionRooms[sid]).to.eql(['room'])
          expect(@server.iorooms.sessionSockets[sid].length).to.eql(1)
        done()
        return true

  it "finds all sessions in a given room", (done) ->
    sessionIds = @server.iorooms.roomSessions["room"]
    @server.iorooms.getSessionsInRoom "room", (err, inRoom) =>
      expect(err).to.be(null)
      expect(sessionIds.length).to.eql(inRoom.length)
      for sessid in sessionIds
        # Check if inRoom contains the session, using _.isEqual for deep equality.
        expect(_.any inRoom, (s) -> _.isEqual(sessid, s.sid)).to.be(true)

      @server.iorooms.getSessionsInRoom "blah", (err, empty) ->
        expect(err).to.be(null)
        expect(empty).to.eql([])
        done()

  it "sends a message", (done) ->
    @browser.fill("#message", "Calling Martha")
    @browser.pressButton("#sendMessage")
    waitFor =>
      messages = @browser2.text("#messages")
      if messages == "Calling Martha"
        done()
        return true

  it "receives a message", (done) ->
    @browser2.fill("#message", "Calling George")
    @browser2.pressButton("#sendMessage")
    waitFor =>
      messages = @browser.text("#messages")
      if messages == "Calling George"
        done()
        return true

  it "leaves a room", (done) ->
    @browser.pressButton("#leaveRoom")
    socketID = @browser.evaluate("socket.socket.sessionid")
    waitFor =>
      if not _.contains @server.io.rooms["/iorooms/room"], socketID
        done()
