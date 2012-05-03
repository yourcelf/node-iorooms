# This is a simple server for executing jasmine's tests.
express     = require 'express'
socketio    = require 'socket.io'
connect     = require 'connect'
uuid        = require 'node-uuid'
RoomManager = require('./iorooms').RoomManager

start = ->
  app = express.createServer()
  sessionStore = new connect.session.MemoryStore
  app.configure ->
    app.use express.cookieParser()
    app.use express.session
      secret: "shhh don't tell abc123"
      store: sessionStore
      key: "express.sid"
    app.use express.static(__dirname + '/static')

  app.get '/', (req, res) ->
    res.render 'test.jade', layout: false

  io = socketio.listen(app, "log level": 0)
  iorooms = new RoomManager("/iorooms", io, sessionStore, {
    #logger: { debug: console.log, error: console.log }
  })
  iorooms.authorizeConnection = (session, callback) ->
    # Set a user id, for fun and profit.
    unless session.user_id?
      session.user_id = uuid.v4()
      sessionStore.set session.sid, session, callback
    else
      callback(null)

  iorooms.on "message", (socket, data) ->
    socket.broadcast.to(data.room).emit "message", data

  app.listen 3000

  return {app, io, iorooms}

if require.main == module
  start()

module.exports = { start }
