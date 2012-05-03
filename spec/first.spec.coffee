Browser = require 'zombie'
expect  = require 'expect.js'
_       = require 'underscore'

waitFor = (callback) ->
  interval = setInterval ->
    if callback()
      clearInterval(interval)
  , 100


describe "iorooms", ->
  before ->
    @server = require('../testserver').start()
  after ->
    @server.app.close()

  it "connects to the socket", (done) ->
    @browser = new Browser()
    @browser2 = new Browser()
    count = 2
    @browser.visit "http://localhost:3000", ->
      count -= 1
    @browser2.visit "http://localhost:3000", ->
      count -= 1

    waitFor =>
      socketIDs = (socketID for socketID, session of @server.iorooms.socketSessionMap)
      if socketIDs.length == 2
        done()
        return true

  it "connects to a room", (done) ->
    @browser.fill("#room", "room")
    @browser2.fill("#room", "room")

    @browser.pressButton("#joinRoom")
    @browser2.pressButton("#joinRoom")


    waitFor =>
      if @server.io.rooms['/iorooms/room']?.length == 2
        userIds = (id for id, obj of @server.iorooms.getUsers("room").others)
        expect(_.unique(userIds)).to.eql(userIds)
        expect(userIds.length).to.be(2)
        done()
        return true

  it "sets a name", (done) ->
    @browser.fill("#name", "George")
    @browser2.fill("#name", "Martha")
    @browser.pressButton("#setName")
    @browser2.pressButton("#setName")
    waitFor =>
      george_id = @browser.evaluate("window.self_id")
      martha_users = @browser2.evaluate("window.users")
      if martha_users[george_id].name == "George"
        done()
        return true

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

