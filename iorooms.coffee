#
# Manage rooms with express sessions and socket IO.
#

events      = require 'events'
parseCookie = require('connect').utils.parseCookie
_           = require 'underscore'

class RoomManager extends events.EventEmitter
  constructor: (route, io, store, options) ->
    @socketSessionMap = {}
    @route = route or "/iorooms"
    @io = io
    @store = store
    @roomSessions = {}
    @sessionRooms = {}

    _.extend this, options

    @setIOAuthorization()
    @setIOConnection()
  
  authorizeConnection: (session, callback) =>
    # Use this function to determine whether or not a session can connect to
    # the socket.  If not, call the callback with a truthy value (probably an
    # error message) as the first argument.
    #
    # Could also be used to set properties for a new session like a userID.
    callback(null)

  authorizeJoinRoom: (session, room, callback) =>
    # Use this function to determine whether or not a session can connect to
    # the room.  If not, call the callback with a truthy value (probably an
    # error message) as the first argument.
    callback(null)

  saveSession: (session, callback) =>
    @store.set session.sid, session, callback

  setIOAuthorization: =>
    @io.set "authorization", (handshake, callback) =>
      unless handshake.headers.cookie
        callback("Cookie missing.", false)
      else
        cookie = parseCookie(handshake.headers.cookie)
        sessionID = cookie['express.sid']
        @store.get sessionID, (err, session) =>
          if err? or not session
            callback(err?.message or "Error acquiring session", false)
          else
            handshake.session = session
            handshake.session.sid = sessionID
            @authorizeConnection session, (err) =>
              if err? then return callback(err, false)
              @saveSession session, (err) =>
                if err?
                  callback(err, false)
                else
                  callback(null, true)

  setIOConnection: =>
    @io.of(@route).on 'connection', (socket) =>
      # Map socket ID to session on connection.  There may be multiple sockets
      # per session, if one has multiple tabs/windows open.
      socket.session = socket.handshake.session
      unless socket.session.sockets
        socket.session.sockets = []
      socket.session.sockets.push(socket.id)
      socket.on 'join', (data) => @join(socket, data.room)
      socket.on 'leave', (data) => @leave(socket, data.room)
      socket.on 'disconnect', (data) => @disconnect(socket)

  onChannel: (message, callback) ->
    @io.of(@route).on 'connection', (socket) ->
      socket.on message, (data) -> callback(socket, data)

  join: (socket, room) =>
    # Request to join a room.  Expects a data payload of the form:
    # {
    #   room: <room name>
    # }
    unless room?
      socket.emit "error", error: "Room not specified"

    @authorizeJoinRoom socket.session, room, (err) =>
      if err? then return socket.emit "error", error: err
      socket.join room
      unless socket.session.rooms?
        socket.session.rooms = []
      first = _.contains socket.session.rooms, room
      unless first
        socket.session.rooms.push(room)
        @saveSession(socket.session)
      @emit "join", {
        socket: socket
        room: room
        first: first
      }

  leave: (socket, room) =>
    # Request to leave a room.  Expects a data payload of the form:
    # {
    #   room: <room name>
    # }
    unless room?
      socket.emit "error", error: "Room not specified"
      return
    socket.leave(room)

    # See if this session has socket connected to this room.
    roomClients = @io.rooms["#{@route}/#{room}"]
    otherSocketFound = false
    for socketID in socket.session.sockets
      if roomClients[socketID]?
        otherSocketFound = true
        break

    unless otherSocketFound
      socket.session.rooms = _.reject socket.session.rooms, (a) -> a == room
      @saveSession(socket.session)

    @emit "leave", {
      socket: socket
      room: room
      last: not otherSocketFound
    }

  disconnect: (socket) =>
    # Disconnect the socket. Leave any rooms that the socket is in.
    for room, connected of @io.roomClients[socket.id]
      # chomp off the route part to get the room name.
      room = room.substring(@route.length + 1)
      if room then @leave socket, {room: room}
    socket.session.sockets = _.reject socket.session.sockets, socket.id
    @saveSession socket.session.sid, socket.session

module.exports = { RoomManager }
