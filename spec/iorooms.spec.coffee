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
        for sid, sessionStr of @server.iorooms.store.sessions
          session = JSON.parse(sessionStr)
          expect(session.rooms).to.eql(["room"])
          expect(session.sockets.length).to.eql(1)
        done()
        return true

  it "finds all sessions in a given room", ->
    console.log @server
    sessions = (JSON.parse(sessionStr) for sid, sessionStr of @server.iorooms.store.sessions)
    inRoom = @server.iorooms.getSessionsInRoom("room")
    expect(sessions.length).to.eql(inRoom.length)
    for sess in sessions
      # Check if inRoom contains the session, using _.isEqual for deep equality.
      expect(_.any inRoom, (a) -> _.isEqual(sess, a)).to.be(true)

    empty = @server.iorooms.getSessionsInRoom("blah")
    expect(empty).to.eql([])


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
      unless _.contains @server.io.rooms["/iorooms/room"], socketID
        done()
